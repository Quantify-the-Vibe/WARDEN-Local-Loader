WARDEN4 Implementation Slice P1.T1.S1 Operator Shell Bootstrap v1
Status: Planned Slice Class: Phase-local execution Write Scope: SwiftUI operator shell surfaces and directly supporting docs/tests for P1.T1.S1
Objective
Execute P1.T1.S1 inside Phase 01 Usable MVP Loader Path without expanding beyond one bounded implementation claim.
Claim
Launch one SwiftUI loader shell that visibly exposes the pi-mono button, model selector placeholder, load button, and runtime status area.
Parent Phase
- `WARDEN4_Phase_01_Usable_MVP_Loader_Path_v1.md`
Parent Track
- Operator Surface And Discovery
Changes In Scope
- implement the bounded shell surface required for P1.T1.S1
- add only the directly supporting app bootstrap, view state, and smoke support needed for this shell path
- update directly dependent docs or tests inside the declared write scope only
Explicit Out Of Scope
- live model discovery
- real model loading
- HTTP endpoints
- pi-mono request handling
Verification
- `swift build`
- launch the operator shell locally
- repository user live test:
  - confirm the window opens
  - confirm the pi-mono button is visible
  - confirm the model selector placeholder is visible
  - confirm the load button is visible
Evidence
- one bounded build result exists for the shell
- one bounded launch result exists for the shell
- one live user confirmation exists for visible controls
Closure Condition
This slice closes when:
- the SwiftUI loader shell launches
- the shell visibly exposes the bounded control set for slice 1
- one direct automated build check passes
- the repository user performs and confirms the live shell test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P1.T1.S2 unless an explicit blocking defect in the shell path requires bounded remediation first.
