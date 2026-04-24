WARDEN4 Implementation Slice P3.T3.S1 Reclaim Failure State Integrity And Degraded Lock v1
Status: Planned Slice Class: Phase-local execution Write Scope: Reclaim-failure handling, status projection, and directly supporting docs/tests for P3.T3.S1
Objective
Execute P3.T3.S1 inside Phase 03 WML v0.3 Resilience And Admission without expanding beyond one bounded implementation claim.
Claim
When memory reclaim verification fails or times out, runtime state remains degraded and locked for load reuse instead of reporting healthy idle.
Parent Phase
- `WARDEN4_Phase_03_WML_V03_Resilience_And_Admission_v1.md`
Parent Track
- Recovery Integrity And Boundary Discipline
Changes In Scope
- block automatic transition to healthy reusable idle on reclaim-failure paths
- surface `degraded_locked` projection coherently across status and UI
- require explicit operator recovery action for reuse after reclaim-failure lock
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- restart/backoff policy changes
- memory estimation algorithm changes
- bridge request translation changes
Verification
- automated reclaim-failure lock test
- automated healthy-idle suppression test
- repository user live test:
  - force reclaim-failure path and confirm runtime stays degraded locked until explicit recovery
Evidence
- one reclaim-failure lock path exists
- one healthy-idle suppression rule exists
- one live user confirmation exists for degraded lock behavior
Closure Condition
This slice closes when:
- reclaim-failure path does not claim healthy idle
- reuse remains blocked until explicit operator recovery
- one direct automated reclaim-lock check passes
- one direct automated healthy-idle suppression check passes
- the repository user performs and confirms the live reclaim-failure lock test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P3.T3.S2 unless reclaim-state logic requires bounded remediation first.

