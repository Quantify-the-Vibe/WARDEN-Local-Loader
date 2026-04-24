WARDEN4 Implementation Slice P2.T2.S3 Budget Reporting In Status Surfaces v1
Status: Planned Slice Class: Phase-local execution Write Scope: Status contract, operator budget surfaces, and directly supporting docs/tests for P2.T2.S3
Objective
Execute P2.T2.S3 inside Phase 02 WML v0.2 Host Protective Runtime without expanding beyond one bounded implementation claim.
Claim
Expose budget summary, admission result, and reclaim result coherently through `GET /status` and the operator shell so the runtime state is inspectable.
Parent Phase
- `WARDEN4_Phase_02_WML_V02_Host_Protective_Runtime_v1.md`
Parent Track
- Budget Verification And Reclaim
Changes In Scope
- add budget-report fields to the canonical status contract
- surface supervisor-facing budget state in the operator shell
- expose last admission and reclaim result coherently
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- restart policy changes
- fail-fast recovery
- new client features beyond coherent status display
- second backend work
Verification
- automated status-contract test for budget fields
- automated UI/view-model projection test for budget visibility
- repository user live test:
  - confirm budget and admission state are visible in the operator shell
  - confirm status JSON exposes the same bounded budget information
Evidence
- one bounded budget report shape exists
- one bounded operator budget surface exists
- one live user confirmation exists for contract and UI visibility
Closure Condition
This slice closes when:
- `GET /status` exposes the bounded budget report shape
- the operator shell shows the same bounded budget state coherently
- one direct automated status-contract check passes
- one direct automated budget-projection check passes
- the repository user performs and confirms the live budget-report test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P2.T3.S1 unless budget reporting requires bounded remediation first.
