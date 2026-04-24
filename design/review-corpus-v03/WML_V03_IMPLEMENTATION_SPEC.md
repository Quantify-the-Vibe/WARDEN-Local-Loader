# WML v0.3 Implementation Spec

## Document Status

- status: active execution source
- purpose: authoritative implementation source for the next WEC-Py v0.3 corpus
- version target: WML v0.3
- predecessor baseline:
  - `docs/WML_V02_IMPLEMENTATION_SPEC.md`
- supersedes as planning source for execution:
  - `docs/WML_V03_PLANNING_SPEC.md`

## Objective

Improve runtime resilience and measurement rigor without changing the accepted v0.2 authority model.

v0.3 must:

- preserve loader-owned runtime authority
- keep host-protective fail-closed behavior
- improve supervision behavior for hangs and repeated instability
- improve memory estimation confidence for admission decisions
- enforce generation-time admission against KV-cache growth
- keep compatibility behavior aligned with canonical control semantics

## Implemented Baseline Carried From v0.2

Already implemented:

- one active runtime lane
- pre-spawn admission gate
- post-load budget verification
- reclaim verification after reset
- supervisor-owned crash accounting
- fail-fast transition
- bridge-visible structured recovery semantics

## Scope

In scope for v0.3:

- restart backoff execution under supervisor ownership
- timeout-to-supervisor failure classification
- conservative memory-estimation confidence model upgrade
- degraded-mode operator/status projection
- bridge/control recovery-alignment hardening

Out of scope for v0.3:

- second backend implementation
- multi-model concurrency
- canonical bridge promotion
- distributed runtime control
- transcript/session product semantics

## Frozen Decisions

### 1) Restart Triggers

Supervisor restart policy applies on:

- unexpected helper exit
- helper ready timeout during load
- helper response timeout during generate

These are treated as crash-equivalent signals for instability accounting.

### 2) Restart Backoff Schedule

Backoff schedule:

- attempt 1: 2 seconds
- attempt 2: 4 seconds
- attempt 3: 8 seconds

Crash window rule:

- maximum 3 crash-equivalent events inside one crash window
- crash window duration must be mathematically compatible with timeout-based crash events
- invariant: `crash_window_seconds >= (max_crash_equivalent_timeout_seconds * 3)`
- default profile for current timeout baseline: `900s` window when timeout class can be `300s`
- event count above that window enters `failed_fast`
- automatic restart stops in `failed_fast`

### 3) Timeout Classification

Timeout classes:

- `helper_ready_timeout` for load readiness timeout
- `helper_generate_timeout` for generation response timeout

Classification policy:

- both classes are crash-equivalent for supervisor instability accounting
- both classes return structured failure to callers
- both classes update operator-visible supervision status

### 4) Memory Estimation Confidence Model

Admission projection uses conservative maximum of:

- filesystem model-size estimate + fixed startup overhead + generation headroom
- observed post-load footprint delta baseline for that model ID (if available)
- hardware allocation evidence signal when available (Metal allocation APIs), otherwise remain on conservative fallback

Policy:

- use higher of the two projections
- if confidence is insufficient, fail closed
- never lower projection due to optimistic inference

Load-settlement rule:

- replace fixed timer assumptions with evidence-based settlement
- model load is considered settled only after memory delta is flat across three consecutive polling ticks
- if settlement does not stabilize within bounded timeout, fail closed

Generation-time admission rule:

- every generate request must run a pre-generate budget check
- projected usage must include context-length-sensitive KV-cache growth estimate
- if projected post-generate footprint may exceed ceiling, refuse generation with structured failure
- no generate path may bypass this gate

### 5) Bridge Policy

v0.3 bridge compatibility policy:

- bridge is translation-only by default
- bridge must not initiate implicit auto-load in default mode
- explicit model load remains a canonical control action on `:8787`
- optional bridge auto-load may exist only behind explicit compatibility flag and must still enforce canonical admission policy
- bridge must surface canonical failure/recovery semantics unchanged

Second backend decision:

- deferred to v0.4 unless explicitly reopened by user

## Runtime State Model

Canonical states remain:

- `bootstrapping`
- `idle`
- `loading`
- `ready`
- `failed`
- `failed_fast`

v0.3 addition:

- degraded-mode projection in status surfaces
- degraded mode is a projection over canonical state, not a new canonical state

Projection rules:

- `failed` with restart-eligible signal -> `degraded`
- `failed_fast` -> `degraded_locked`
- reclaim verification timeout/failure -> `degraded_locked` (not healthy `idle`)
- `idle`/`ready` -> `healthy`

## Contract Requirements

Canonical control surface (`:8787`) must continue:

- `GET /status`
- `GET /models`
- `POST /load`
- `POST /generate`
- `POST /reset`

Compatibility bridge (`:8080`) must continue:

- `POST /v1/chat/completions`

v0.3 required status fields:

- `runtime_state`
- `supervisor_state`
- `crash_window_count`
- `crash_limit`
- `failed_fast_active`
- timeout-classified last failure code when applicable
- degraded-mode projection (`healthy|degraded|degraded_locked`)

## Failure Semantics

Fail-closed requirements:

- admission cannot prove safe -> deny load
- post-load verification over ceiling -> terminate helper and fail
- reclaim verification fails or times out -> no healthy idle claim and no automatic transition to reusable idle
- timeout-classified crash-equivalent event above policy -> `failed_fast`

Operator recovery rule:

- only explicit reset can clear `failed_fast`

## Verification Requirements

Required automated evidence:

- restart backoff timing policy test
- crash-window transition test with timeout-classified events
- timeout classification mapping test (`helper_ready_timeout`, `helper_generate_timeout`)
- estimation model max-of-projections test
- degraded-mode projection test
- bridge/control recovery payload alignment test

Required live evidence:

- repeated crash-equivalent events trigger bounded restart then `failed_fast`
- timeout-classified failures appear coherently in shell and bridge
- reset clears `failed_fast` and restores reusable lane when reclaim passes

## Explicit Rejections

- do not weaken 12GB fail-closed posture
- do not let bridge semantics override canonical loader policy
- do not admit second backend in v0.3 by default
- do not reopen v0.2 closure language

## Corpus Generation Gate

This spec is ready for v0.3 PEM generation when:

- backlog marks v0.3 implementation spec freeze complete
- review corpus includes this file as active source
- archived documents remain excluded from corpus input
