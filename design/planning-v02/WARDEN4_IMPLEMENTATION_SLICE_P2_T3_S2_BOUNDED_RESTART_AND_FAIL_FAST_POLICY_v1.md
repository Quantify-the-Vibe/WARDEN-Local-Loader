WARDEN4 Implementation Slice P2.T3.S2 Bounded Restart And Fail-Fast Policy v1
Status: Planned Slice Class: Phase-local execution Write Scope: Restart window, fail-fast transitions, and directly supporting docs/tests for P2.T3.S2
Objective
Execute P2.T3.S2 inside Phase 02 W4L v0.2 Host Protective Runtime without expanding beyond one bounded implementation claim.
Claim
Repeated helper instability inside the admitted crash window triggers bounded restart attempts and then a `failed_fast` state that blocks further load admission until explicit operator recovery.
Parent Phase
- `WARDEN4_Phase_02_W4L_V02_Host_Protective_Runtime_v1.md`
Parent Track
- Supervision And Fail-Fast
Changes In Scope
- implement the admitted restart window and back-off sequence
- transition to `failed_fast` after repeated instability
- block load admission while `failed_fast` is active
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- broader product retry semantics
- second backend work
- distributed recovery logic
- non-operator recovery controls
Verification
- automated restart-window test
- automated fail-fast gate test
- automated explicit recovery-clearance test
- repository user live test:
  - confirm repeated instability reaches `failed_fast`
  - confirm explicit operator action is required before reuse
Evidence
- one bounded restart policy exists
- one bounded fail-fast gate exists
- one live user confirmation exists for fail-fast and recovery behavior
Closure Condition
This slice closes when:
- repeated helper instability enters `failed_fast` after the admitted restart window
- load admission is blocked while `failed_fast` is active
- one direct automated restart-window check passes
- one direct automated fail-fast gate check passes
- one direct automated recovery-clearance check passes
- the repository user performs and confirms the live fail-fast and recovery test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P2.T3.S3 unless bounded restart or fail-fast requires bounded remediation first.
