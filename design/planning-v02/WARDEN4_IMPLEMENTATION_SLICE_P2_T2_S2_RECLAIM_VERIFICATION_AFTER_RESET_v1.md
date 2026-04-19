WARDEN4 Implementation Slice P2.T2.S2 Reclaim Verification After Reset v1
Status: Planned Slice Class: Phase-local execution Write Scope: Reset reclaim verification and directly supporting docs/tests for P2.T2.S2
Objective
Execute P2.T2.S2 inside Phase 02 W4L v0.2 Host Protective Runtime without expanding beyond one bounded implementation claim.
Claim
Reset does not return healthy reusable idle until helper termination and reclaim verification both pass within the configured reclaim slack.
Parent Phase
- `WARDEN4_Phase_02_W4L_V02_Host_Protective_Runtime_v1.md`
Parent Track
- Budget Verification And Reclaim
Changes In Scope
- measure post-reset footprint
- compare post-reset footprint against baseline plus tolerated reclaim slack
- hold the runtime out of healthy idle if reclaim is insufficient
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- admission formula redesign
- crash restart policy
- fail-fast recovery
- second backend work
Verification
- automated reclaim success test
- automated reclaim failure-path test
- repository user live test:
  - load one model
  - reset the lane
  - confirm healthy idle is only returned on successful reclaim
Evidence
- one bounded reclaim verification path exists
- one bounded reclaim failure path exists
- one live user confirmation exists for reset and reuse behavior
Closure Condition
This slice closes when:
- reset verifies reclaim before claiming healthy idle
- insufficient reclaim prevents healthy reuse and returns structured failure
- one direct automated reclaim success check passes
- one direct automated reclaim failure-path check passes
- the repository user performs and confirms the live reset and reuse test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P2.T2.S3 unless reclaim verification requires bounded remediation first.
