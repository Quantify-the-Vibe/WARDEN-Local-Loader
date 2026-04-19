# W4L v0.4 Planning Spec

## Document Status

- status: planning draft
- purpose: bounded authority candidate for the next PEM corpus
- predecessor baseline:
  - `docs/W4L_V03_IMPLEMENTATION_SPEC.md`

## Objective

Define a minimal, low-risk v0.4 scope that improves operator usability and model compatibility without weakening v0.3 fail-closed guarantees.

## Locked Baseline From v0.3

Carry forward as fixed:

- 12GB fail-closed budget posture
- timeout crash-equivalent supervision
- bounded restart/backoff with `failed_fast`
- reclaim-failure degraded lock
- OpenAI bridge translation-only default

## Candidate v0.4 Scope

Admit only if explicitly frozen before PEM generation:

1. chat-template compatibility fallback hardening
- keep structured fallback for models with missing tokenizer chat templates
- add deterministic request-path behavior for template-missing models
- keep canonical structured error reporting when fallback cannot safely apply

2. operator UX clarity for degraded and lock states
- compact status visibility for long runtime messages
- explicit visibility for recovery action and blocked reason codes
- no authority-model change in UI layer

3. bridge compatibility policy finalization
- decide whether legacy auto-load flag remains admitted or removed
- keep bridge non-authoritative regardless of decision

4. packaging and release ergonomics
- preserve reproducible app/binary build path
- ensure CI artifacts remain launchable with clear provenance

## Explicit Out Of Scope

- second backend implementation
- multi-model concurrency
- distributed runtime control
- session persistence or transcript product semantics

## Required Freeze Points Before v0.4 PEM Generation

- legacy bridge auto-load flag decision:
  - keep as feature flag, or remove entirely
- exact template-fallback decision tree:
  - fallback path, refusal path, and invariant checks
- UI projection contract:
  - required fields and maximum verbosity behavior
- live-test gate definition per slice:
  - explicit user confirmation remains mandatory

## Acceptance Gate For This Planning Draft

This file can become execution authority only when:

- each freeze point above is resolved without `PENDING` ambiguity
- one bounded slice list is derived from this file only
- WEC-Py corpus is regenerated from the frozen v0.4 source
