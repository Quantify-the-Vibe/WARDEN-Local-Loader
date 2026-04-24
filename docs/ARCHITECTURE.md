# Architecture

## Document Status

- status: canonical spec-input
- purpose: architecture source for the next implementation spec
- reflects:
  - implemented topology
  - admitted topology changes
- does not claim:
  - that admitted topology changes already exist in code

## Objective

Define a loader architecture that:

- keeps the runtime boundary local and explicit
- contains backend crashes
- protects a 16GB unified-memory host
- stays small enough to evolve without becoming a distributed monolith

## Architectural Characteristics

Priority order:

- fault isolation
- memory safety
- operability
- evolvability
- simplicity

Deferred:

- throughput optimization
- multi-client concurrency
- session persistence
- advanced telemetry

## System Context

- parent system:
  - `/Users/kikbot/Documents/WARDEN4/WARDEN4-Rebuild/`
- local inference subsystem:
  - this repo
- first client:
  - `pi-mono`
- operator surface:
  - `WMLShell.app`
- local model root:
  - `/Users/kikbot/.models/mlx/`
- target host:
  - 16GB unified-memory Apple Silicon macOS machine

## Implemented Topology

Implemented now:

1. operator launches `WMLShell.app`
2. `WMLShellViewModel` initializes on the main actor
3. model discovery scans `/Users/kikbot/.models/mlx/`
4. control HTTP server starts on `:8787`
5. OpenAI-compatible bridge starts on `:8080`
6. operator or bridge triggers a load
7. `MLXBackendLoader` spawns `mlx_loader_helper.py`
8. helper loads model and tokenizer
9. helper owns model residency
10. requests route through Swift to the helper over stdin/stdout JSON framing
11. operator reset terminates helper and returns loader to `idle`

## Admitted Topology Changes

Admitted for the next spec:

1. extract a `LoaderSupervisor` authority from `WMLShellViewModel`
2. move memory admission and restart decisions into that authority
3. keep backend helper as a separate OS process
4. keep client bridge outside backend-specific code
5. keep one active runtime lane

The lowest-risk target topology is:

- `WMLShellView`
  - operator controls only
- `WMLShellViewModel`
  - UI-facing state projection only
- `LoaderSupervisor`
  - runtime authority
  - memory admission authority
  - crash and restart authority
- `BackendLoader`
  - backend seam
- `MLXBackendLoader`
  - subprocess adapter
- `mlx_loader_helper.py`
  - MLX residency and generation host
- `LocalHTTPServer`
  - local transport only

## Boundary Rules

- `pi-mono` remains outside the loader boundary
- bridge code remains outside MLX-specific code
- helper remains outside UI process memory space
- UI must not become the runtime authority
- backend adapter must not become the public API

## Ownership Split

### Parent System

Owns:

- product composition
- cross-subsystem UX
- decisions above the loader boundary

### WMLShellView

Owns:

- controls
- visibility
- operator feedback

Does not own:

- runtime policy
- memory policy
- backend semantics

### WMLShellViewModel

Implemented now:

- discovery state
- selected model state
- HTTP delegate behavior
- status summaries

Target next state:

- becomes a projection layer over supervisor-owned runtime state
- should stop owning direct policy decisions once supervisor exists

### LoaderSupervisor

Not implemented now.
Admitted for next spec.

Should own:

- active lifecycle state
- memory admission decision
- load authorization
- reset authorization
- crash counting
- restart decision
- fail-fast transition

### BackendLoader

Owns the backend seam only.

Minimum interface direction:

- `load(model:)`
- `generate(prompt:)`
- `generateChat(messages:)`
- `shutdown()`

### MLXBackendLoader

Owns:

- helper process spawn
- helper termination
- helper ready parsing
- helper request/response framing
- backend-specific failure translation

### mlx_loader_helper.py

Owns:

- model load via `mlx_lm.load()`
- model residency
- generation via `mlx_lm.generate()`
- chat template usage
- fallback prompt building when tokenizer template is absent

### LocalHTTPServer

Owns:

- socket accept
- HTTP parse
- delegate routing
- response rendering

Instance roles:

- control server on `:8787`
- compatibility bridge on `:8080`

## Runtime Surface

### Canonical Control Surface

Routes:

- `GET /status`
- `GET /models`
- `POST /load`
- `POST /generate`
- `POST /reset`

This remains the loader-owned contract.

### Compatibility Surface

Route:

- `POST /v1/chat/completions`

Purpose:

- allow `pi-mono` to connect without redesigning `pi-mono`

Architecture rule:

- compatibility bridge may adapt transport shape
- compatibility bridge must not own loader policy

## Lifecycle Model

Implemented now:

- `bootstrapping`
- `idle`
- `loading`
- `ready`
- `failed`

Admitted next states:

- `serving`
- `reclaiming`
- `failed_fast`

Next spec must define:

- exact transition rules
- transition owner
- transition side effects

## Memory Architecture

This section is intentionally careful.

Required target:

- protect the host by refusing unsafe loads above the admitted 12GB ceiling

Not yet implemented:

- enforcement metric
- reservation mechanism
- reclaim metric

Next spec must define:

### Measurement Source

- one named measurable quantity
- one source of truth for admission and verification

### Budget Model

- static model footprint estimate
- startup overhead estimate
- request-time growth headroom
- host reserve

### Admission Rule

- exact formula for load allow/deny
- exact fail-closed behavior when evidence is insufficient

### Reclaim Rule

- exact reset behavior
- exact post-reset measurement window
- exact reclaim success threshold

Until then, “12GB ceiling” is a design target, not a truth claim about the current runtime.

## Failure Architecture

Implemented now:

- backend helper crash does not directly crash the UI process
- backend errors are surfaced structurally across the adapter seam
- reset exists as a manual recovery path

Admitted next behavior:

- helper crash observed by supervisor
- bounded restart attempts
- crash window accounting
- transition to `failed_fast` after repeated instability
- explicit operator reset required to exit `failed_fast`

The architecture is supervision-inspired, not Erlang-equivalent.
The next spec must define the actual supervision semantics instead of implying them.

## Anti-Patterns Explicitly Rejected

- `pi-mono` calling MLX directly
- bridge logic becoming the runtime authority
- UI process holding backend-specific policy
- present-tense documentation for unimplemented safety guarantees
- adding multiple runtime lanes before one safe lane exists
- treating restart loops as reliability without crash-window limits

## What The Next Spec Must Produce

The next implementation spec should be able to answer these directly:

- what exactly is measured for the 12GB rule
- where admission is computed
- when admission is recomputed
- what reset must prove about reclaim
- what state the supervisor owns
- how crash detection works
- when restart is allowed
- when fail-fast is entered
- which contract fields expose budget and failure state

If the spec cannot answer those precisely, it is not ready for WEC-Py decomposition.
