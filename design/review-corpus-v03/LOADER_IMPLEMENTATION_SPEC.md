# Loader Implementation Spec

## Document Status

- status: canonical spec-input
- purpose: source material for the next implementation spec to be fed into WEC-Py
- reflects:
  - implemented loader slice
  - admitted next architecture changes
- does not claim:
  - that slice-2 memory controls already exist
  - that crash supervision is already implemented

## Problem Statement

Implemented proof already exists:

- discover model
- load model
- connect `pi-mono`
- send prompt
- receive response

That proof is necessary but insufficient.

Current gap:

- the loader can run a local model path, but it does not yet provide a defensible safety envelope for a 16GB unified-memory host
- the current implementation contains the backend in a subprocess, but it does not yet implement a formal supervisor, bounded restart rules, or memory admission controls
- the current docs previously mixed target safety properties with implemented behavior, which makes them unsafe as spec input

## Objective

Primary objective for the next spec:

- preserve the working subsystem boundary
- add memory safety as a real enforced behavior
- add fault isolation as an explicit designed mechanism
- do this without expanding the loader into a chat product or a distributed monolith

Secondary objective:

- produce a spec that WEC-Py can decompose into PEMs without ambiguity about what is implemented now versus what must be built next

## Authority Model

- parent system:
  - `WARDEN4-Rebuild`
- this repo owns:
  - local model runtime control
  - operator-facing runtime state
  - client-facing local inference boundary
- `pi-mono` owns:
  - chat UX
  - prompt composition UX
  - response display
- backend adapters own:
  - backend-specific runtime behavior behind the loader boundary

## Implemented Now

VERIFIED current implementation:

- SwiftUI macOS operator app exists
- one active model lane exists
- model discovery scans `/Users/kikbot/.models/mlx/`
- `BackendLoader` protocol exists
- `MLXBackendLoader` exists
- persistent Python helper exists at `tools/mlx_loader_helper.py`
- control HTTP server exists at `:8787`
- OpenAI-compatible bridge exists at `:8080/v1/chat/completions`
- `pi-mono` connects through the bridge
- reset path exists
- packaged `.app` bundle exists under `dist/LoaderShell.app`

Current limitations:

- no enforced memory ceiling exists in code
- no formal admission control exists in code
- no reclaim verification exists in code
- no explicit `LoaderSupervisor` actor exists in code
- no bounded restart policy exists in code
- no token-by-token backend streaming exists; bridge compatibility is present, but helper generation remains whole-response

## Admitted Next Changes

These changes are admitted for the next implementation spec, but are not yet implemented:

- explicit memory admission before every load
- enforced host-protection ceiling targeting 12GB maximum loader-managed footprint
- fail-closed refusal when safe admission cannot be proven
- post-load budget verification
- post-reset reclaim verification
- supervisor extraction from `LoaderShellViewModel`
- crash containment rules and bounded restart policy
- structured memory budget reporting in status and backend-ready outputs

## Hard Constraints

- loader core language remains Swift
- operator surface remains SwiftUI
- MLX helper remains subordinate to the Swift loader
- MLX remains the first implemented backend
- backend seam remains generic
- loader must prefer smallest-responsibility components over premature framework growth
- loader must protect the host machine before serving a client request
- if safe runtime admission cannot be established, the load path must fail closed

## Resource Envelope

User-directed resource target:

- host machine: 16GB unified memory macOS Apple Silicon
- desired maximum loader-managed footprint: 12GB

Important rigor rule:

- the next spec must define exactly what “12GB” means before treating it as enforceable canon

That spec must name:

- measurement source
  - example classes: process resident memory, phys_footprint, combined app + helper footprint, Metal allocations if observable
- measurement scope
  - loader app only
  - helper only
  - combined loader-owned processes
- admission formula
  - static model footprint
  - startup overhead
  - generation-time headroom
  - reclaim headroom
- failure rule
  - what counts as “cannot prove safe admission”

Until those are defined and implemented, the 12GB rule is a required target, not an implemented guarantee.

## Lowest-Risk Design Direction

Recommended design direction for the next spec:

- supervision-inspired local process containment
- one supervisor-owned active backend lane
- one memory budget authority
- one admission decision per load
- one reclaim verification after reset

This is the lowest-risk option because it:

- preserves the working subsystem boundary
- preserves client independence
- avoids letting `pi-mono` pull policy into the bridge
- avoids overbuilding a distributed architecture for a local subsystem

## Invariants

These invariants are already valid or should remain valid across the next rewrite:

- clients must not call MLX internals directly
- backend-specific code must not own the public system boundary
- `pi-mono` integration must not redefine loader semantics around `pi-mono`-only needs
- product-level prompt rewriting is not loader authority
- product-level output rewriting is not loader authority
- `shutdown()` must remain callable and idempotent
- reset must remain an operator-controlled recovery action
- backend failures crossing the adapter boundary must remain structured

## Required Clarifications For The Next Spec

The next spec must resolve these design questions explicitly:

### Memory Admission

- what exact metric is enforced
- how projected load cost is estimated before spawn
- what fixed reserve is kept for the host and non-loader processes
- whether per-generate checks are needed for KV-cache growth

### Reclaim

- what “memory released back to the system” means operationally on macOS
- what measurement is taken after reset
- what threshold counts as successful reclaim
- what failure state follows if reclaim is insufficient

### Supervision

- what process and state the supervisor owns
- what crash signals it recognizes
- which state survives helper crash
- how in-flight requests fail when helper dies
- exact restart back-off and crash-window rules

### Contract

- which routes are canonical
- which routes are compatibility-only
- whether memory budget reports appear on `:8787`, `:8080`, or both
- whether OpenAI bridge auto-load stays admitted or becomes explicit-only

## Implemented Contract Versus Target Contract

Implemented control contract now:

- `GET /status`
- `GET /models`
- `POST /load`
- `POST /generate`
- `POST /reset`

Implemented compatibility bridge now:

- `POST /v1/chat/completions`

Next-spec rule:

- `:8787` remains the canonical loader contract
- `:8080` remains a compatibility bridge unless explicitly promoted by a later decision

## Non-Goals

- turning the loader into a chat product
- multi-model concurrency
- remote provider orchestration
- product-level transcript features
- advanced telemetry before memory and supervision are sound
- client-specific policy encoded inside backend adapters

## Open Questions

- PENDING:
  - exact measurable memory quantity for the 12GB ceiling
- PENDING:
  - whether allocation can be modeled conservatively enough pre-load to justify “allocate up front” semantics on MLX/macOS
- PENDING:
  - whether generation-time KV growth is material enough to require request admission, not only load admission
- PENDING:
  - whether supervisor should be an actor plus state machine or a smaller extracted coordinator with one actor-owned critical section

## Revision Trigger

Revise this document if any of these change:

- host memory target changes
- backend count changes from one implemented backend to two
- `pi-mono` stops being the first client
- the compatibility bridge becomes canonical
- real measurement evidence shows the 12GB target is infeasible for admitted model sizes without stricter admission
