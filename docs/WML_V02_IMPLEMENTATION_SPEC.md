# WML v0.2 Implementation Spec

## Document Status

- status: closed implemented baseline
- purpose: authoritative record of the completed WML v0.2 execution corpus
- version target: WML v0.2
- supersedes as execution source:
  - v0.1 MVP slice corpus
- superseded by planning for next work:
  - `docs/WML_V03_PLANNING_SPEC.md`

## Objective

Upgrade the working WARDEN Model Loader from a proven MVP runtime path into a host-protective local inference subsystem that:

- preserves the current working client boundary
- protects a 16GB unified-memory macOS host
- fails closed when safe runtime admission cannot be proven
- contains helper crashes without taking down the operator process
- verifies reclaim after reset before treating the lane as healthy for reuse

## Implemented Baseline

Implemented and working now:

- SwiftUI macOS operator app
- model discovery from `/Users/kikbot/.models/mlx/`
- one active model lane
- `BackendLoader` seam
- `MLXBackendLoader` implementation
- persistent Python MLX helper
- control contract on `:8787`
- OpenAI-compatible bridge on `:8080/v1/chat/completions`
- `pi-mono` end-to-end connection through the bridge
- reset path
- packaged macOS `.app`
- memory measurement baseline
- explicit budget constants
- pre-spawn admission gate
- post-load budget verification
- reclaim verification after reset
- explicit supervisor authority
- bounded fail-fast policy
- `failed_fast` state
- compatibility-bridge recovery alignment

Still not implemented from later possible phases:

- executed restart backoff
- helper timeout supervision as a first-class crash signal
- refined MLX memory-cost estimation beyond conservative file-size projection
- second backend validation

## Closure Summary

v0.2 closed the host-protective runtime upgrade it was created to execute.

Closed results:

- every load is admitted or refused through an explicit budget decision path
- unsafe loads fail closed before helper spawn
- post-load over-budget state is detected and terminated
- reset does not claim healthy reusable `idle` until reclaim verification passes
- repeated instability transitions the loader into `failed_fast`
- operator shell and compatibility bridge now expose aligned recovery semantics

Live-gated execution completed through `PEM-008`.

## Scope Implemented In v0.2

Implemented in v0.2:

- memory budget measurement model
- load admission decision
- post-load budget verification
- post-reset reclaim verification
- supervisor extraction and state ownership
- helper crash detection
- bounded fail-fast policy
- contract additions needed to expose the above

Explicitly left for later phases:

- second backend implementation
- multi-model concurrency
- distributed coordination
- transcript persistence
- prompt or output rewriting as product behavior
- tool-calling semantics as a loader concern
- true token-by-token backend streaming
- executed restart backoff

## Constraints Preserved

- host target:
  - Apple Silicon macOS with 16GB unified memory
- maximum admitted loader-managed memory target:
  - 12GB
- if safe admission cannot be established:
  - refuse load
- `pi-mono` remains first client, not authority model
- `:8787` remains canonical loader contract
- `:8080` remains compatibility bridge
- helper remains a separate OS process
- UI process must survive helper crash

## Architectural Outcome

### Parent Boundary

- parent system:
  - `WARDEN4-Rebuild`
- loader remains one bounded subsystem

### Runtime Boundary

- `WMLShellView`
  - operator controls only
- `WMLShellViewModel`
  - UI projection and bridge to supervisor-owned state
- `LoaderSupervisor`
  - runtime authority for v0.2
- `BackendLoader`
  - backend seam
- `MLXBackendLoader`
  - MLX subprocess adapter
- `mlx_loader_helper.py`
  - MLX residency and generation host

### Authority Split

`LoaderSupervisor` owns:

- lifecycle state
- admission decision
- post-load verification decision
- reclaim verification decision
- crash counting
- fail-fast transition

`WMLShellViewModel` owns:

- presentation state derived from supervisor state
- UI actions forwarded to supervisor
- HTTP delegate forwarding

`MLXBackendLoader` owns:

- helper spawn and terminate
- helper protocol framing
- helper readiness parsing
- backend failure translation

## v0.2 Acceptance Criteria

Closed as satisfied:

- unsafe loads are refused before helper spawn
- post-load over-budget state is detected and closed
- reset verifies reclaim before declaring healthy idle
- helper crash does not crash UI process
- repeated helper instability enters `failed_fast`
- operator can see budget and failure state
- `pi-mono` receives coherent failure when admission or fail-fast blocks service

## Verification Record

Satisfied automated evidence:

- admission allow test
- admission deny test
- post-load over-budget path test
- reset reclaim success test
- reclaim failure path test
- helper crash restart-window test
- fail-fast gate test
- bridge failure-mapping test
- operator recovery-state projection test

Satisfied live evidence:

- repository user validated admission-denied behavior
- repository user validated reset and reuse behavior
- repository user validated fail-fast and operator recovery behavior
- repository user validated bridge-visible recovery alignment

## Closed PEM Decomposition

The completed WEC-Py corpus produced PEMs clustered around:

- supervisor extraction
- memory measurement plumbing
- admission decision
- post-load verification
- reclaim verification
- crash detection
- restart policy
- fail-fast recovery
- contract/status updates

Completed PEM set:

- `PEM-001` memory measurement and budget constants baseline
- `PEM-002` admission gate before helper spawn
- `PEM-003` post-load budget verification
- `PEM-004` reclaim verification after reset
- `PEM-005` budget reporting in status surfaces
- `PEM-006` supervisor extraction and crash accounting
- `PEM-007` bounded restart and fail-fast policy
- `PEM-008` compatibility bridge and operator recovery alignment

## Revision Triggers

Do not reopen this spec unless:

- measurement source changes
- host target changes
- ceiling target changes
- a second backend is admitted
- compatibility bridge is promoted into canonical authority
- a proven implementation defect requires bounded v0.2 remediation
