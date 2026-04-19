WARDEN4 Implementation Slice P2.T2.S1 Post-Load Budget Verification v1
Status: Planned Slice Class: Phase-local execution Write Scope: Ready-state budget verification and directly supporting docs/tests for P2.T2.S1
Objective
Execute P2.T2.S1 inside Phase 02 W4L v0.2 Host Protective Runtime without expanding beyond one bounded implementation claim.
Claim
After helper readiness, verify the actual combined footprint and tear down the lane if the real post-load footprint exceeds the allowed ceiling.
Parent Phase
- `WARDEN4_Phase_02_W4L_V02_Host_Protective_Runtime_v1.md`
Parent Track
- Budget Verification And Reclaim
Changes In Scope
- measure combined footprint after helper-ready
- compare measured footprint against the configured ceiling
- terminate helper and return structured failure when the real footprint is over budget
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- pre-spawn admission design changes
- reclaim verification
- bounded restart policy
- fail-fast recovery
Verification
- automated ready-under-budget test
- automated post-load over-budget failure test
- repository user live test:
  - load one model that remains healthy
  - confirm over-budget failure state is visible if the bounded test path is triggered
Evidence
- one bounded post-load verification path exists
- one bounded over-budget shutdown path exists
- one live user confirmation exists for visible post-load state
Closure Condition
This slice closes when:
- post-load footprint is checked after helper-ready
- over-budget post-load state is terminated and surfaced structurally
- one direct automated healthy ready-path check passes
- one direct automated over-budget failure-path check passes
- the repository user performs and confirms the live post-load verification test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P2.T2.S2 unless post-load verification requires bounded remediation first.
