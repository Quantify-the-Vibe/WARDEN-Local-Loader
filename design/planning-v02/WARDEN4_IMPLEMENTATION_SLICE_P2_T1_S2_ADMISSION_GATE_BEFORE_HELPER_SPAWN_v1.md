WARDEN4 Implementation Slice P2.T1.S2 Admission Gate Before Helper Spawn v1
Status: Planned Slice Class: Phase-local execution Write Scope: Load admission logic, structured refusal path, and directly supporting docs/tests for P2.T1.S2
Objective
Execute P2.T1.S2 inside Phase 02 W4L v0.2 Host Protective Runtime without expanding beyond one bounded implementation claim.
Claim
Refuse unsafe loads before helper spawn by using the selected measurement source, explicit budget constants, and fail-closed structured error paths.
Parent Phase
- `WARDEN4_Phase_02_W4L_V02_Host_Protective_Runtime_v1.md`
Parent Track
- Memory Budget Authority
Changes In Scope
- compute projected load cost before helper spawn
- block load when required measurement data is unavailable
- block load when projected total exceeds the configured ceiling
- surface structured refusal through the canonical control contract and operator state
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- post-load ceiling verification
- reclaim verification
- crash restart policy
- fail-fast recovery
Verification
- automated allow-path admission test
- automated deny-path admission test for unavailable measurement
- automated deny-path admission test for ceiling overflow
- repository user live test:
  - attempt one admitted load and confirm it still works
  - attempt one denied load path and confirm the refusal is visible and structured
Evidence
- one bounded pre-spawn admission authority exists
- one bounded fail-closed refusal path exists
- one live user confirmation exists for admitted and denied behavior
Closure Condition
This slice closes when:
- unsafe loads are refused before helper spawn
- structured failure codes are returned for admission denial
- one direct automated allow-path admission check passes
- two direct automated deny-path admission checks pass
- the repository user performs and confirms the live admission test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P2.T2.S1 unless an admission defect requires bounded remediation first.
