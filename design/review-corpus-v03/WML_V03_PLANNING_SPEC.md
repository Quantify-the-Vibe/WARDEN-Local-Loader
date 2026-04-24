# WML v0.3 Planning Spec

## Document Status

- status: planning draft
- purpose: bounded authority candidate for the next post-v0.2 PEM corpus
- version target: WML v0.3
- predecessor baseline:
  - `docs/WML_V02_IMPLEMENTATION_SPEC.md`

## Objective

Advance the closed WML v0.2 runtime without reopening its accepted authority model.

v0.3 should improve operational resilience and measurement quality while preserving:

- loader-owned runtime authority
- `pi-mono` as first client only
- canonical control contract on `:8787`
- compatibility bridge on `:8080`
- one active model lane

## Closed v0.2 Baseline

Implemented baseline inherited from v0.2:

- memory measurement baseline
- pre-spawn admission gate
- post-load verification
- reclaim verification after reset
- supervisor-owned crash accounting
- bounded fail-fast transition
- bridge-visible structured recovery semantics

v0.3 must treat that baseline as closed unless an implementation defect reopens it explicitly.

## Problem Statement

The loader now protects the host and exposes coherent recovery semantics, but several resilience paths remain conservative rather than fully operational.

Current bounded gaps:

- crash policy counts instability but does not yet execute timed restart backoff
- helper protocol timeout handling is not yet a first-class supervision signal
- MLX memory-cost estimation is conservative and file-size based
- operator UX communicates recovery state but not a richer degraded-mode posture
- only one backend implementation exists, so seam validity is proven structurally but not comparatively

## Scope Candidates

Primary v0.3 candidates:

- restart backoff execution
- helper protocol timeout supervision
- improved MLX memory-cost estimation
- operator-visible degraded-mode and recovery affordances
- one bounded second-adapter validation slice

Out of scope unless explicitly admitted later:

- multi-model concurrency
- distributed runtime control
- prompt-product semantics
- transcript persistence
- turning the compatibility bridge into canonical authority

## Lowest-Risk Recommendation

Recommended v0.3 order:

1. implement restart backoff execution
2. admit helper protocol timeout as a crash-equivalent supervision signal
3. improve MLX cost estimation and document confidence bounds
4. refine operator degraded-mode and recovery presentation
5. only then consider one bounded second-adapter validation slice

Reason:

- this sequence strengthens the existing authority boundary before expanding backend scope
- it improves runtime evidence quality before increasing surface area
- it preserves the v0.2 client/runtime split

## Planning Constraints

- do not weaken the 12GB fail-closed posture
- do not let bridge behavior redefine canonical loader semantics
- do not add new client-coupled behavior as a shortcut for resilience work
- do not open second-backend work until supervision behavior is operationally stronger

## Required Freeze Before New PEM Generation

Before generating a v0.3 corpus, freeze:

- restart trigger rules
- restart backoff schedule
- timeout thresholds and classification
- whether timeout counts inside the same crash window as process exit
- acceptable confidence model for MLX memory-cost estimation
- whether second-backend work is admitted in v0.3 or deferred to v0.4

## Candidate Acceptance Direction

v0.3 is complete only if:

- restart behavior is explicit and bounded
- timeout failures map coherently into supervisor state
- operator and bridge remain aligned on recovery semantics
- new measurement logic improves evidence quality without weakening fail-closed behavior
- any adapter expansion preserves the existing authority split

## Next Canonical Move

Use this planning draft to derive one active v0.3 implementation spec.

Do not generate a new PEM corpus directly from free-form notes or stale v0.2 execution language.
