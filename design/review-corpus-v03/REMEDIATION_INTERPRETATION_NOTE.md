# W4L Remediation Interpretation Note

## Purpose

This note helps reviewers classify remediation suggestions correctly.

The main failure mode in prior review rounds was mixing:

- current code defects
- admitted v0.3 planning gaps
- archived design-note assumptions

## Use This Classification

When a remediation is proposed, classify it as one of:

- current-code remediation
- admitted v0.3 planning item
- archived-doc remediation only
- architectural option, not mandatory

## Current-Code Remediation

These are valid live remediation targets against the implemented loader:

- per-generate admission or another explicit generation-time KV-growth guard
- better memory-cost estimation than static directory walk alone
- clearer bridge-boundary policy if auto-load is no longer admitted
- timeout supervision once it is explicitly wired into runtime state

These items are live because the current code still:

- uses file-system model-cost estimation
- relies on fixed headroom values
- does not model generation-time KV growth directly
- keeps bridge auto-load behavior in the compatibility surface

## Admitted v0.3 Planning Items

These are valid next-phase items, but not current implementation contradictions:

- helper timeout supervision as a first-class crash signal
- restart backoff execution
- tighter MLX memory-cost estimation
- degraded-mode operator UX
- second-adapter validation

If a reviewer raises these, treat them as planning-direction feedback unless they point to a concrete current-code bug.

## Archived-Doc Remediation Only

These should not be treated as current-code defects unless they are reintroduced into active canon:

- replacing a `500ms` post-load settle timer
- fixing a `5s` reclaim timeout that still returns `idle`
- warning-only reclaim timeout behavior
- any critique that depends on archived `slice 2` notes as if they were the live implementation

Those claims come from archived historical notes, not the current loader code.

## Architectural Options, Not Mandatory Outcomes

These may be good recommendations, but they are not logically forced by the current canon:

- making the `:8080` bridge translation-only immediately
- replacing directory-walk estimation entirely with Metal APIs
- synchronizing timeout durations and crash-window durations as the only acceptable supervision design

Current canon allows these to remain open design choices until they are explicitly frozen.

## Review Discipline

Before accepting a remediation suggestion:

1. verify it targets behavior inside the approved review corpus
2. check whether the behavior exists in current code, active canon, or archived notes
3. classify it using this note
4. only then decide whether it is:
   - a bug fix
   - a planning input
   - a canon-cleanup task

## Canon Rule

Archived documents outside this review corpus do not overrule the current implementation or active planning direction.
