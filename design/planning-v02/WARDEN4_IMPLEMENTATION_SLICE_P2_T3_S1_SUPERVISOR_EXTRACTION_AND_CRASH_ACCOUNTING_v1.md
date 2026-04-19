WARDEN4 Implementation Slice P2.T3.S1 Supervisor Extraction And Crash Accounting v1
Status: Planned Slice Class: Phase-local execution Write Scope: Supervisor authority, crash accounting, and directly supporting docs/tests for P2.T3.S1
Objective
Execute P2.T3.S1 inside Phase 02 W4L v0.2 Host Protective Runtime without expanding beyond one bounded implementation claim.
Claim
Extract one supervisor-owned runtime authority that owns lifecycle state, crash accounting, and structured helper failure handling while keeping the UI process alive.
Parent Phase
- `WARDEN4_Phase_02_W4L_V02_Host_Protective_Runtime_v1.md`
Parent Track
- Supervision And Fail-Fast
Changes In Scope
- create one explicit supervisor authority for lifecycle state
- route helper crash signals into supervisor-owned accounting
- ensure helper failure does not crash the operator process
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- bounded restart back-off policy
- fail-fast recovery gate
- new memory formulas beyond already-admitted state
- second backend work
Verification
- automated helper-crash detection test
- automated UI-process-survives-helper-failure test
- repository user live test:
  - trigger or simulate one helper failure
  - confirm the operator shell stays alive and shows failed state coherently
Evidence
- one bounded supervisor authority exists
- one bounded crash accounting path exists
- one live user confirmation exists for helper crash containment
Closure Condition
This slice closes when:
- supervisor owns runtime lifecycle state and crash accounting
- helper crash transitions runtime state structurally without crashing the UI process
- one direct automated helper-crash detection check passes
- one direct automated UI-survival check passes
- the repository user performs and confirms the live crash-containment test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P2.T3.S2 unless supervisor extraction requires bounded remediation first.
