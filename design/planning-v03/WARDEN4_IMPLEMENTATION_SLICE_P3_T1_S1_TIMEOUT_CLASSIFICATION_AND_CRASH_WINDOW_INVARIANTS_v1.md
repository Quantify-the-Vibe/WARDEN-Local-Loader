WARDEN4 Implementation Slice P3.T1.S1 Timeout Classification And Crash Window Invariants v1
Status: Planned Slice Class: Phase-local execution Write Scope: Supervisor timeout mapping, crash-window invariants, and directly supporting docs/tests for P3.T1.S1
Objective
Execute P3.T1.S1 inside Phase 03 WML v0.3 Resilience And Admission without expanding beyond one bounded implementation claim.
Claim
Timeout failures are classified as crash-equivalent events and counted by a crash-window policy that is mathematically compatible with timeout durations.
Parent Phase
- `WARDEN4_Phase_03_WML_V03_Resilience_And_Admission_v1.md`
Parent Track
- Supervision Math And Restart Behavior
Changes In Scope
- add explicit timeout classes for ready-timeout and generate-timeout
- map timeout classes into supervisor crash-equivalent accounting
- enforce crash-window invariant: `crash_window_seconds >= (max_crash_equivalent_timeout_seconds * 3)`
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- restart backoff execution
- memory admission algorithm changes
- bridge policy changes
Verification
- automated timeout-class mapping test
- automated crash-window invariant test
- repository user live test:
  - trigger timeout-classified failures and confirm they appear in status/failure outputs
Evidence
- one timeout classification map exists
- one crash-window invariant exists and is enforced
- one live user confirmation exists for timeout-class visibility
Closure Condition
This slice closes when:
- timeout classes are represented as crash-equivalent events
- invalid crash-window to timeout configurations are rejected
- one direct automated timeout mapping check passes
- one direct automated invariant check passes
- the repository user performs and confirms the live timeout-visibility test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P3.T1.S2 unless timeout mapping requires bounded remediation first.

