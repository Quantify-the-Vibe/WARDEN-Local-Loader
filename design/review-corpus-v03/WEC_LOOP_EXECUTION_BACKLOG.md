# WEC Loop Execution Backlog

## Document Status

- status: canonical planning input
- purpose: record v0.2 closure and define the next bounded planning gate
- scope: post-v0.2 planning only

## Planning Objective

- keep v0.2 closed as implemented baseline
- prevent drift back into ad hoc post-phase changes
- define the next bounded spec input for v0.3 before any new PEM generation

This backlog is no longer for v0.2 slice execution.
That work is already complete and user-validated.

## Completed Baseline

Already implemented:

- operator app
- model discovery
- MLX backend seam
- Python helper residency
- control contract on `:8787`
- OpenAI-compatible bridge on `:8080`
- `pi-mono` end-to-end connection
- reset path
- macOS app packaging
- memory measurement baseline
- pre-spawn admission gate
- post-load budget verification
- reclaim verification
- supervisor extraction
- bounded fail-fast policy
- compatibility-bridge recovery alignment

## Closed v0.2 Corpus

Closed planning root:

- `design/planning-v02/`

Closed execution corpus:

- `runtime_data/wecpy/authoritative-pems/`

Closed result:

- Phase 02 is complete
- `8/8` PEMs were implemented
- live gates passed through `PEM-008`

## Next Planning Gate

Before new PEM generation:

- v0.2 must remain marked closed in canon
- one bounded v0.3 planning source must exist
- restart and timeout semantics must be frozen before corpus generation
- second-backend scope must be explicitly admitted or deferred

## New Workstream

### Milestone 1: Freeze v0.2 Closure

Purpose:

- ensure the repo stops treating v0.2 as active unfinished work

Required outcomes:

- implemented-now lists match code
- v0.2 is marked closed baseline
- active-next planning pointer moves to v0.3

Status:

- complete

### Milestone 2: Freeze v0.3 Planning Source

Purpose:

- define one bounded authority candidate for the next corpus

Current planning source:

- `design/review-corpus-v03/WML_V03_IMPLEMENTATION_SPEC.md`
- `design/planning-v03/`

Required freeze points:

- restart trigger rules
- restart backoff schedule
- timeout classification
- MLX cost-estimation confidence model
- second-adapter admission decision

Exit condition:

- planning draft is precise enough to become one implementation spec without hidden authority changes

Status:

- complete

### Milestone 3: Generate v0.3 Corpus

Purpose:

- derive the next PEM set from a frozen v0.3 implementation spec only

Entry gate:

- Milestone 2 complete
- v0.3 planning slice source frozen under `design/planning-v03/`
- live test gate requirement preserved between every generated PEM

Status:

- ready to start

## Lowest-Risk v0.3 Direction

Recommended order:

1. restart backoff execution
2. helper protocol timeout supervision
3. tighter MLX memory-cost estimation
4. degraded-mode operator UX
5. bounded second-adapter validation if still admitted

## Explicit Planning Rejections

- do not continue changing runtime behavior without a new frozen spec
- do not regenerate PEMs from stale v0.2 execution language
- do not let bridge behavior redefine canonical loader authority
- do not admit second-backend work before supervision semantics are frozen
