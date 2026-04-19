# Fault Tolerance

## Document Status

- status: archived design note
- canonical status:
  - not active canon
  - not approved review corpus input
- superseded by:
  - `docs/W4L_V02_IMPLEMENTATION_SPEC.md`
  - `docs/W4L_V03_PLANNING_SPEC.md`
- reason:
  - contains superseded supervision and restart planning that does not describe current code

## Archive Notice

This file is preserved as historical design material only.

It contains superseded or not-yet-implemented assumptions, including:

- timeout handling as part of future supervisor behavior
- restart back-off execution
- supervisor-owned lifecycle that exceeds current code
- references to `MEMORY_MANAGEMENT.md` as canonical input

Do not review this file as if it describes the current implementation.
Do not use this file as WEC-Py spec input.
Do not use this file in the active design review corpus.

## Problem Statement

- the MLX helper is a separate OS process and can crash or be OOM-killed at any time
- the current implementation has no crash detection, no restart policy, and no supervised recovery path
- `LoaderShellViewModel` manages backend state inline, conflating UI state with lifecycle management
- if the helper exits unexpectedly, the next generate call will hit a `model_not_loaded` error
- there is no operator-visible signal that the backend has gone away between requests
- the goal: `LoaderShell.app` must never exit due to a backend failure, and the operator must always see accurate state

## Design Principles

### From Erlang

Erlang's fault model provides the best available frame for this problem. The key ideas applied to this runtime:

- process isolation is the primary defense
  - the helper runs as a separate OS process; this is the strongest isolation available
  - if it is killed, the parent process is unaffected at the OS level
  - the loader must make this guarantee structural, not accidental

- let it crash, but supervise the restart
  - do not defensively guard every operation inside the helper
  - let the helper crash cleanly and let the supervisor decide what to do next
  - the supervisor is the only component with restart authority

- supervisor owns the lifecycle, not the worker
  - the helper does not manage its own restart
  - the supervisor holds the restart count, crash timestamps, and back-off state
  - the worker only needs to do its job or crash

- maximum restart density limits
  - if the same worker crashes too many times in a short window, it is not a transient failure
  - the supervisor transitions to `failed_fast` and surfaces the problem to the operator
  - automatic restart stops; operator action is required

- clean shutdown is cooperative, forced shutdown is the fallback
  - send `{"command":"shutdown"}` to stdin first
  - if the process does not exit cleanly within the timeout, send `SIGTERM`
  - if still alive after SIGTERM timeout, the OS will handle it on next load attempt


## Erlang-to-Swift Mapping

- Erlang `process` with message passing → OS subprocess + stdin/stdout framed JSON
- Erlang `supervisor` process → `LoaderSupervisor` actor (Swift, main actor isolated)
- Erlang `one_for_one` restart strategy → Task retry loop inside `LoaderSupervisor`
- Erlang `max_restarts` / `max_seconds` → `crashCount` + `crashWindowStart` tracked in `LoaderSupervisor`
- Erlang `monitor` → `process.terminationHandler` + `process.isRunning` polling
- Erlang `let it crash` → `try await` with catch at the supervisor boundary only; no defensive guards inside the helper
- Erlang `EXIT` signal propagation → `BackendFailureReport` returned from adapter boundary
- Erlang supervisor `:permanent` child → restart always attempted unless `failed_fast`
- Erlang supervisor `:transient` child → not applicable in slice 2; all crashes treated as `permanent` until `failed_fast`

## Failure Domains

### Domain 1 — Python Helper Process

- boundary: separate OS process
- failure modes:
  - unhandled Python exception during load → exits with non-zero, stdout pipe closes
  - OOM kill (kernel SIGKILL during generation) → exits, pipe closes
  - stuck in `generate()` past timeout → read timeout fires in Swift, detected as `helper_timeout`
  - clean shutdown → exits with status 0 after processing `shutdown` command
- detection:
  - `process.isRunning == false` after load or generate error
  - `readOneLine` returns timeout error (`helper_timeout`)
  - stdout pipe returns empty data

### Domain 2 — MLXBackendLoader Actor

- boundary: Swift actor
- failure modes:
  - spawn failure (`process.run()` throws) → propagated as `BackendFailureReport`
  - protocol framing error (invalid JSON from helper) → `invalid_helper_payload`
  - ready timeout (helper does not emit ready within 120s) → `helper_timeout`
  - generate timeout (no response within 300s) → `helper_timeout`
- containment: all errors become `BackendFailureReport` before crossing the adapter boundary
- no error from this domain propagates as an untyped Swift `Error` past the `BackendLoader` protocol

### Domain 3 — LoaderSupervisor Actor (slice 2 target)

- boundary: Swift actor owning backend lifecycle
- failure modes:
  - crash-window exceeded → `failed_fast` transition, no further auto-restart
  - memory ceiling breach on restart attempt → `memory_ceiling_exceeded`, `failed_fast` promoted
  - restart back-off timeout still in progress → restart deferred, supervisor returns pending status

### Domain 4 — SwiftUI Main Actor

- boundary: main thread, `@MainActor`
- invariant: must never be blocked or crashed by any backend operation
- enforcement: all backend I/O runs on `DispatchQueue.global` or in `Task` off the main actor
- no backend error propagates to this domain as an unhandled exception


## LoaderSupervisor Design

### Responsibility Split

- `LoaderSupervisor` owns:
  - backend process lifecycle (spawn, monitor, restart, terminate)
  - crash-window tracking
  - restart back-off state
  - `failed_fast` detection and enforcement
  - memory pre-flight call before every spawn attempt
  - reclaim verification after every shutdown

- `LoaderShellViewModel` retains:
  - selected model state
  - HTTP delegate responsibilities
  - UI-visible status string and detail
  - delegation of all backend lifecycle calls to `LoaderSupervisor`

- `MLXBackendLoader` retains:
  - stdin/stdout protocol implementation
  - generate and shutdown methods
  - no restart logic

### Supervisor State Machine

- `idle`
  - no backend loaded
  - transitions to `loading` when operator initiates load

- `loading`
  - pre-flight in progress or helper spawning
  - transitions to `ready` on `BackendReadyReport`
  - transitions to `failed` on `BackendFailureReport`
  - transitions to `failed_fast` on ceiling breach

- `ready`
  - helper resident and accepting commands
  - transitions to `serving` when a generate request arrives

- `serving`
  - generate in flight
  - transitions to `ready` on successful response
  - transitions to `crashed` if process exits during request

- `crashed`
  - helper exited unexpectedly
  - crash count incremented
  - if crashCount < maxCrashesInWindow: schedule restart after back-off delay
  - if crashCount >= maxCrashesInWindow: transition to `failed_fast`

- `failed_fast`
  - crash window exceeded
  - no automatic restart
  - operator must explicitly reset
  - transitions to `idle` only on operator reset

### Crash Window Parameters

- `maxCrashesInWindow`: 3
- `crashWindowDuration`: 60 seconds
- restart back-off sequence: 2s, 4s, 8s (doubles on each successive crash within window)
- if a crash occurs after the window has expired, count resets to 1 and window starts fresh

### Restart Path

1. crash detected (process exits, `isRunning == false`)
2. increment crash count, record crash timestamp
3. evaluate crash-window condition
4. if `failed_fast` threshold met: surface to operator, stop
5. compute back-off delay for this restart attempt
6. wait for back-off delay
7. call `MemoryBudget.preflight(...)` — memory may have changed since last load
8. if pre-flight fails: surface `memory_ceiling_exceeded`, transition to `failed_fast`
9. if pre-flight passes: attempt `MLXBackendLoader.load(model:)` with the last known selected model
10. if load succeeds: transition to `ready`, surface restart notice to operator
11. if load fails: increment crash count and loop from step 3


## Crash Detection Mechanism

### During Load

- `MLXBackendLoader.load(model:)` reads the first line of stdout with a 120s timeout
- if the helper process exits before emitting the ready payload, the stdout pipe closes
- an empty read from a closed pipe returns empty `Data`
- `readOneLine` detects this and throws `helper_timeout` or `invalid_helper_payload`
- `load(model:)` catches this, calls `shutdown()` defensively, and throws `BackendFailureReport`

### During Generate

- generate sends a command to stdin and reads the response line with a 300s timeout
- if the helper exits mid-generate, the stdout pipe closes
- same empty-read detection path as above
- `generate(prompt:)` or `generateChat(messages:)` throws `BackendFailureReport`

### Between Requests

- CURRENT: no between-request liveness check exists in slice 1
- SLICE 2 TARGET: `LoaderSupervisor` polls `process.isRunning` on a 10s heartbeat timer
- alternatively: when `status == .ready`, the supervisor sends a `{"command":"health"}` probe every 30s
- if probe fails or process is not running, transition to `crashed` and execute restart path

### `process.terminationHandler`

- `Process.terminationHandler` fires on the same dispatch queue the process was started on when the helper exits
- this provides an asynchronous notification without polling
- `LoaderSupervisor` sets this handler at spawn time
- handler captures `[weak self]` and notifies the supervisor actor of the unexpected exit
- this is the primary crash detection signal in slice 2

## Interaction With Memory Management

### On Restart

- the supervisor calls `MemoryBudget.preflight(...)` before every spawn attempt
- this is necessary because the previous crash may not have released memory yet
- if the previous model's memory has not been reclaimed, pre-flight will detect it
- the supervisor should wait for reclaim verification to complete before attempting a restart
- if reclaim times out, the supervisor runs pre-flight against the current actual footprint anyway
- fail-closed if pre-flight fails after a crash; this avoids compounding OOM pressure

### On `failed_fast`

- when entering `failed_fast`, the supervisor calls `shutdown()` if any helper is still running
- this sends the cooperative shutdown command and terminates the process
- reclaim verification runs as a background task
- `failed_fast` state does not block the operator from seeing memory reclaim progress in the status detail

## Implementation Guidance

### Source File

- `Sources/LoaderShell/LoaderSupervisor.swift` — new file for slice 2

### Actor Isolation

- `LoaderSupervisor` is a Swift `actor`
- all state is actor-isolated: crash count, crash timestamps, back-off state, active backend reference
- `LoaderShellViewModel` calls supervisor methods via `await`
- no `LoaderSupervisor` state is accessed directly from the main actor

### Back-off Implementation

- `try await Task.sleep(for: .seconds(backOffSeconds))` inside the supervisor actor
- back-off table: index 0 → 2s, index 1 → 4s, index 2 → 8s, index 3+ → 8s (capped)
- index is the current `crashCount - 1` within the window

### Status Propagation

- supervisor exposes a `@Published`-equivalent via `AsyncStream` or a callback closure
- `LoaderShellViewModel` subscribes and forwards supervisor state changes to `status` and `statusDetail`
- the operator always sees the current supervisor state, even during back-off delay

## Fitness Functions

- main actor safety: no `await` call to `MLXBackendLoader` may appear on the main actor call site without an intervening `Task`
  - verification: Swift concurrency warning audit — `@MainActor` functions must not directly `await` backend I/O
- supervisor authority: no restart logic appears outside `LoaderSupervisor`
  - verification: search for `MLXBackendLoader()` instantiation sites; only `LoaderSupervisor` may create one after slice 2
- `failed_fast` gate: once `failed_fast` is set, no code path may call `load(model:)` without an explicit operator reset
  - verification: unit test — drive crash count past window limit, assert load attempts are rejected
- pre-flight on restart: the restart path in `LoaderSupervisor` must call `MemoryBudget.preflight` before every spawn
  - verification: integration test — mock ceiling at current footprint, trigger restart, assert `memory_ceiling_exceeded` is returned

## Deferred Items

- per-request liveness probe (health command on a timer)
- supervisor hierarchy for multiple backends
- crash report surfacing to WARDEN4-Rebuild parent system
- structured restart event log (crash count, timestamps, back-off history)
