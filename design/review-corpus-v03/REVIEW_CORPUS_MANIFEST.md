# W4L Review Corpus Manifest

## Purpose

This folder is the approved design corpus copy for external review of the current W4L architecture and planning state.

Use this folder when:

- reviewing current loader canon
- preparing design feedback
- comparing v0.2 implemented baseline against v0.3 planning direction

Do not use the broader `docs/` folder when the goal is current-canon review.

## Included Files

- `README.md`
- `W4L_V02_IMPLEMENTATION_SPEC.md`
- `W4L_V03_PLANNING_SPEC.md`
- `W4L_V03_IMPLEMENTATION_SPEC.md`
- `LOADER_IMPLEMENTATION_SPEC.md`
- `ARCHITECTURE.md`
- `INTEGRATION_NOTES_FOR_PI_MONO.md`
- `WEC_LOOP_EXECUTION_BACKLOG.md`
- `REMEDIATION_INTERPRETATION_NOTE.md`

## Explicit Exclusions

Excluded from this review corpus:

- `docs/MEMORY_MANAGEMENT.md`
- `docs/FAULT_TOLERANCE.md`

Reason:

- these are archived historical design notes
- they contain superseded assumptions that do not describe the current implementation
- they should not be treated as active canon or WEC-Py spec input

## Review Rule

If a reviewer cites a design claim from outside this folder, that claim should be treated as non-canonical unless it is separately re-admitted into active canon.

If a reviewer proposes remediation, compare it against `REMEDIATION_INTERPRETATION_NOTE.md` before treating it as a current-code defect, a v0.3 planning item, or an archived-doc artifact.

Active execution authority in this corpus:

- `W4L_V03_IMPLEMENTATION_SPEC.md`
