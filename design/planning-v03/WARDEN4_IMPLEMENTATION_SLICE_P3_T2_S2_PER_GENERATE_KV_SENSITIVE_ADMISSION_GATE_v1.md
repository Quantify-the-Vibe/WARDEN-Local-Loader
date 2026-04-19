WARDEN4 Implementation Slice P3.T2.S2 Per Generate KV Sensitive Admission Gate v1
Status: Planned Slice Class: Phase-local execution Write Scope: Generate-path admission checks, KV-sensitive projection logic, and directly supporting docs/tests for P3.T2.S2
Objective
Execute P3.T2.S2 inside Phase 03 W4L v0.3 Resilience And Admission without expanding beyond one bounded implementation claim.
Claim
Every generate request executes a pre-generate admission gate that projects KV-cache growth and refuses unsafe generation before budget breach occurs.
Parent Phase
- `WARDEN4_Phase_03_W4L_V03_Resilience_And_Admission_v1.md`
Parent Track
- Dynamic Memory Admission
Changes In Scope
- add pre-generate memory projection with context-length-sensitive KV growth estimate
- deny generate when projected usage crosses ceiling
- return structured refusal semantics to operator and bridge surfaces
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- model-load admission changes
- restart/backoff policy changes
- second backend work
Verification
- automated safe-generate admission test
- automated over-budget generate refusal test
- repository user live test:
  - run short prompt then large-context prompt and confirm large-context path is refused before breach
Evidence
- one generate-path admission gate exists
- one structured over-budget refusal path exists
- one live user confirmation exists for KV-sensitive refusal behavior
Closure Condition
This slice closes when:
- generate requests cannot bypass pre-generate admission
- unsafe projected generate is denied with structured failure
- one direct automated safe-admission check passes
- one direct automated over-budget refusal check passes
- the repository user performs and confirms the live KV-sensitive admission test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P3.T3.S1 unless generate admission requires bounded remediation first.

