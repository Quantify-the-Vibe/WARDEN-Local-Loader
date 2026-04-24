# Memory Management

## Document Status

- status: archived design note
- canonical status:
  - not active canon
  - not approved review corpus input
- superseded by:
  - `docs/WML_V02_IMPLEMENTATION_SPEC.md`
  - `docs/WML_V03_PLANNING_SPEC.md`
- reason:
  - contains superseded slice-2 planning assumptions that do not describe current code

## Archive Notice

This file is preserved as historical design material only.

It contains superseded assumptions, including:

- `phys_footprint` as the primary enforced metric
- a `500ms` post-load settle timer
- a `5s` reclaim timeout that still returns `idle`
- warning-only reclaim timeout behavior

Do not review this file as if it describes the current implementation.
Do not use this file as WEC-Py spec input.
Do not use this file in the active design review corpus.

## Problem Statement

- the M2 Pro uses unified memory shared across CPU, GPU, and Neural Engine
- MLX models load directly into this unified pool
- an 8GB model plus MLX KV cache, the Python helper process, the Swift app, and macOS can together exceed 12GB
- if memory pressure becomes critical, macOS will OOM-kill the most expensive process
- the loader has no pre-flight check, no ceiling enforcement, and no reclaim verification
- a naive load attempt against a full memory pool will either hang, produce degraded inference, or be killed by the OS
- this must be a structured, loader-owned failure, not an OS surprise

## Memory Budget Model

### Total Pool

- physical unified memory: 16GB

### Allocation Targets

- macOS system reserve: ~2GB (kernel, daemons, WindowServer)
- `WMLShell.app` process: ~200MB
- `mlx_loader_helper.py` process overhead (excluding model weights): ~300MB
- `pi-mono` process: ~300MB
- Terminal and shell: ~100MB
- total system overhead estimate: ~3GB

### Available for Model Weights Plus KV Cache

- 16GB - 3GB = 13GB theoretical maximum
- apply 1GB safety margin
- usable ceiling: 12GB

### Hard Ceiling

- value: 12,884,901,888 bytes (exactly 12 * 1024 * 1024 * 1024)
- this is not a soft warning threshold
- any load that would project past this value is refused before the helper is spawned
- behavior: fail closed, return structured error, do not proceed


## Physical Footprint Measurement

### Why `phys_footprint` and Not RSS

- `phys_footprint` is the metric Apple's Activity Monitor uses for "Memory" column
- it reports actual physical pages backed by hardware RAM, net of memory-mapped files that are not resident
- on Apple Silicon, unified memory means there is no separate VRAM; GPU allocations appear in this metric
- MLX model weights loaded onto the Metal GPU appear in `phys_footprint` of the Python process
- RSS (`resident_size`) overcounts memory-mapped files and undercounts compressed pages
- `phys_footprint` from `TASK_VM_INFO` is the accurate measure for ceiling enforcement on this hardware

### Measurement Point

- measure the Swift process footprint via `task_info(mach_task_self_, TASK_VM_INFO, ...)`
- this gives the loader app's own footprint
- the Python helper runs as a child process with its own footprint
- to measure the combined footprint before the helper is spawned, measure the Swift process footprint only
- after load, the helper's footprint can be inferred from the difference between post-load and pre-load measurements
- ASSUMED: pre-load Swift process footprint + estimated model size + overhead ≈ post-load system footprint
- PENDING: whether measuring child process footprint directly via `task_for_pid` is needed for reclaim verification

## Pre-flight Algorithm

### Inputs

- current Swift process physical footprint (measured)
- model directory path (from `ModelRecord.localPath`)
- MLX overhead budget constant: 512MB

### Steps

1. call `task_info(mach_task_self_, TASK_VM_INFO, &info, &count)` and read `info.phys_footprint`
2. walk the model directory with `FileManager` enumerator, sum `fileSizeKey` for all entries
3. compute projected = current_footprint + model_dir_bytes + overhead_budget
4. if projected > HARD_CEILING: throw `MemoryError.ceilingExceeded(projected:ceiling:modelEstimate:)`
5. if projected <= HARD_CEILING: proceed to spawn helper

### Model Size Estimation Notes

- directory walk sums all files: weights shards, tokenizer, config, vocabulary
- this is a lower bound: KV cache grows during generation and is not estimated here
- the 512MB overhead budget covers: Python interpreter, mlx-lm library, tokenizer buffers, and early KV cache growth
- actual KV cache at generation time can exceed this for long contexts
- a per-generate ceiling re-check is a slice 2 follow-on item

### Failure Response

- error type: `MemoryError.ceilingExceeded`
- fields: projected bytes, ceiling bytes, model estimate bytes
- behavior: do not spawn helper, return structured failure to caller
- UI consequence: `WMLShellViewModel` transitions to `failed` state, operator sees the structured detail


## Post-Load Verification

### Purpose

- confirm that actual loaded footprint does not exceed the ceiling
- catch cases where the model directory size estimate was a significant undercount
- this is the second gate; pre-flight is the first

### Steps

1. after the helper emits `{"status":"ready"}` on stdout, wait 500ms for allocation to settle
2. re-measure Swift process footprint via `TASK_VM_INFO`
3. ASSUMED: footprint delta since pre-flight ≈ helper process model footprint
4. if measured delta + pre_flight_footprint > HARD_CEILING: call `shutdown()` immediately, return `MemoryError.postLoadCeilingExceeded`
5. if within ceiling: include footprint delta in `BackendReadyReport` as `memoryBudgetReport`

### `BackendReadyReport` Memory Fields (slice 2 addition)

- `preflightFootprintBytes`: Int64 — footprint at time of pre-flight check
- `postLoadFootprintDeltaBytes`: Int64 — increase observed after load settled
- `ceilingBytes`: Int64 — hard ceiling value at load time
- `headroomBytes`: Int64 — ceiling minus (pre-flight + delta)

## Reclaim Verification

### Purpose

- confirm that memory is returned to the system after a reset
- macOS will eventually reclaim, but the loader should verify this before reporting idle
- prevents a rapid reload scenario from double-loading into an already-stressed pool

### Steps

1. after `MLXBackendLoader.shutdown()` completes (helper terminated)
2. record pre-shutdown footprint as `shutdownBaseline`
3. poll every 500ms, re-measure footprint via `TASK_VM_INFO`
4. if footprint returns within 100MB of the baseline recorded before the original load: reclaim confirmed
5. timeout: 5 seconds (10 polls)
6. if timeout without reclaim: emit `reclaim_timeout` warning in status detail, do not fail
7. transition to `idle` regardless; macOS VM manager will complete reclaim asynchronously

### Why Not Fail on Reclaim Timeout

- macOS page reclaim is asynchronous and controlled by the kernel
- the helper process has been terminated; its memory is committed for reclaim
- a reclaim warning informs the operator without blocking the reset path
- if the operator attempts an immediate reload, pre-flight will catch any remaining pressure

## Error Types

### `MemoryError`

- `footprintUnavailable`
  - cause: `task_info` returned non-`KERN_SUCCESS`
  - behavior: treat as fail-closed; do not proceed with load if footprint cannot be measured
- `ceilingExceeded(projected: Int64, ceiling: Int64, modelEstimate: Int64)`
  - cause: pre-flight projected footprint exceeds hard ceiling
  - behavior: fail closed, structured error, no helper spawned
- `postLoadCeilingExceeded(delta: Int64, ceiling: Int64)`
  - cause: actual post-load footprint exceeded ceiling despite passing pre-flight
  - behavior: immediate shutdown, structured error returned to caller
- `reclaimTimeout`
  - cause: footprint did not return to baseline within 5 seconds of shutdown
  - behavior: warning only, idle transition proceeds


## Implementation Design

### `MemoryBudget` Struct

- location: new source file `Sources/WMLShell/MemoryBudget.swift`
- visibility: internal to `WMLShell` module
- responsibilities:
  - expose `currentFootprint() throws -> Int64` — reads `phys_footprint` via `task_info`
  - expose `estimateModelSize(at path: String) -> Int64` — directory walk, sums file sizes
  - expose `preflight(modelPath: String, currentFootprintBytes: Int64) throws` — computes projection, throws on breach
  - expose constants: `hardCeiling`, `overheadBudget`

### `MemoryError` Enum

- location: same file as `MemoryBudget`
- conforms to: `Error`, `LocalizedError`
- cases: `footprintUnavailable`, `ceilingExceeded`, `postLoadCeilingExceeded`, `reclaimTimeout`

### Integration in `MLXBackendLoader`

- `load(model:)` calls `MemoryBudget.preflight(...)` before `process.run()`
- if pre-flight throws, re-throw as `BackendFailureReport` with code `memory_ceiling_exceeded`
- after helper emits ready payload, call post-load verification
- if post-load check throws, call `shutdown()` and re-throw as `BackendFailureReport`
- include memory fields in returned `BackendReadyReport`

### Integration in `WMLShellViewModel`

- `loadButtonPressed()` handles `BackendFailureReport` with code `memory_ceiling_exceeded` distinctly
- status detail surfaces the projected vs. ceiling values to the operator
- UI state transitions to `failed` with enough detail for the operator to understand the constraint

### Integration in Reset Path

- `resetButtonPressed()` after calling `await backendLoader.shutdown()` initiates reclaim verification
- reclaim check runs as a background `Task`
- status detail updates with reclaim confirmation or timeout warning
- `idle` transition happens regardless of reclaim poll outcome

## Fitness Functions

- pre-flight gate: every code path that calls `MLXBackendLoader.load(model:)` must call `MemoryBudget.preflight` first
  - verification: code review gate — search for `process.run()` calls not preceded by a preflight call
- ceiling value: `MemoryBudget.hardCeiling` must be the single source of truth for the 12GB constant
  - verification: no other file defines a 12GB or `12 * 1024 * 1024 * 1024` constant
- fail-closed behavior: `footprintUnavailable` must not silently permit a load
  - verification: unit test — mock `task_info` failure and assert load returns structured error, not success
- reclaim poll must not block the main actor
  - verification: reclaim Task must be spawned as a detached or background task, not awaited on the call site

## Deferred Items

- per-generate ceiling re-check for KV cache growth
- Metal memory pressure API integration (`MTLDevice.currentAllocatedSize`) for GPU-specific view
- multi-lane load: total footprint of all residents checked against ceiling before admitting a second model
- configurable ceiling value via operator preference or environment variable
