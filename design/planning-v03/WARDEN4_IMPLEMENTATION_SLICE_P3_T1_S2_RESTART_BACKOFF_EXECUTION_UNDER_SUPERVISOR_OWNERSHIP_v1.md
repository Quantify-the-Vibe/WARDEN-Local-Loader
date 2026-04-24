WARDEN4 Implementation Slice P3.T1.S2 Restart Backoff Execution Under Supervisor Ownership v1
Status: Planned Slice Class: Phase-local execution Write Scope: Restart scheduling, retry limits, fail-fast transitions, and directly supporting docs/tests for P3.T1.S2
Objective
Execute P3.T1.S2 inside Phase 03 WML v0.3 Resilience And Admission without expanding beyond one bounded implementation claim.
Claim
Supervisor executes bounded restart backoff for crash-equivalent events and enters `failed_fast` once policy limits are crossed.
Parent Phase
- `WARDEN4_Phase_03_WML_V03_Resilience_And_Admission_v1.md`
Parent Track
- Supervision Math And Restart Behavior
Changes In Scope
- implement restart backoff schedule using the frozen bounded sequence
- enforce restart-attempt ceiling in the active crash window
- stop automatic restart when `failed_fast` is active
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- timeout classification logic changes
- memory estimation changes
- bridge policy changes
Verification
- automated backoff-sequence timing test
- automated retry-limit to `failed_fast` transition test
- repository user live test:
  - reproduce repeated crash-equivalent failures and confirm bounded restart then `failed_fast`
Evidence
- one bounded backoff executor exists
- one deterministic transition path to `failed_fast` exists
- one live user confirmation exists for bounded restart behavior
Closure Condition
This slice closes when:
- restart attempts follow the frozen bounded schedule
- `failed_fast` is entered after policy threshold breaches
- automatic restart remains blocked while `failed_fast` is active
- one direct automated backoff check passes
- one direct automated fail-fast transition check passes
- the repository user performs and confirms the live bounded-restart test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P3.T2.S1 unless restart policy requires bounded remediation first.

