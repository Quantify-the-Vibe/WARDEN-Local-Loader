WARDEN4 Implementation Slice P3.T3.S2 Bridge Translation Only Default And Explicit Load Policy v1
Status: Planned Slice Class: Phase-local execution Write Scope: Compatibility bridge request handling, load-authority routing, and directly supporting docs/tests for P3.T3.S2
Objective
Execute P3.T3.S2 inside Phase 03 W4L v0.3 Resilience And Admission without expanding beyond one bounded implementation claim.
Claim
Compatibility bridge operates as translation-only by default and does not implicitly mutate canonical model-load authority.
Parent Phase
- `WARDEN4_Phase_03_W4L_V03_Resilience_And_Admission_v1.md`
Parent Track
- Recovery Integrity And Boundary Discipline
Changes In Scope
- disable implicit auto-load in bridge default behavior
- require explicit load action through canonical control path before generation
- preserve optional compatibility flag for legacy auto-load only when explicitly enabled
- align bridge refusal semantics with canonical loader failure semantics
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- second backend work
- distributed runtime control changes
- new client-specific behavior outside compatibility layer
Verification
- automated translation-only default test
- automated explicit-load-required behavior test
- repository user live test:
  - call bridge generate without prior load and confirm explicit-load refusal semantics
Evidence
- one translation-only default exists
- one explicit-load-required path exists
- one live user confirmation exists for bridge boundary behavior
Closure Condition
This slice closes when:
- bridge default does not auto-load
- bridge requests without explicit load are rejected coherently
- optional legacy auto-load compatibility remains feature-flag constrained
- one direct automated translation-only check passes
- one direct automated explicit-load-required check passes
- the repository user performs and confirms the live bridge-boundary test
- the phase exit gate remains blocked until that live confirmation is recorded
Follow-On
Phase 03 closes unless bounded remediation is required.
