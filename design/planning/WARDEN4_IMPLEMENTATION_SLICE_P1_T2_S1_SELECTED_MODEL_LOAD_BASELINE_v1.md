WARDEN4 Implementation Slice P1.T2.S1 Selected Model Load Baseline v1
Status: Planned Slice Class: Phase-local execution Write Scope: Backend seam, load path, runtime state, and directly supporting docs/tests for P1.T2.S1
Objective
Execute P1.T2.S1 inside Phase 01 Usable MVP Loader Path without expanding beyond one bounded implementation claim.
Claim
Load one selected MLX model through the loader boundary using default behavior and no extra kwargs.
Parent Phase
- `WARDEN4_Phase_01_Usable_MVP_Loader_Path_v1.md`
Parent Track
- Runtime Load Path
Changes In Scope
- add the smallest backend adapter seam required for MLX
- implement one selected-model load path
- surface bounded runtime state for loading, ready, and failure
- update directly dependent docs or tests inside the declared write scope only
Explicit Out Of Scope
- non-MLX backend implementation
- full admission policy
- full reclaim verification
- pi-mono prompt path
Verification
- `swift build`
- bounded local load smoke for one real MLX model
- repository user live test:
  - select one real model
  - press load
  - confirm the shell reports ready or a structured failure
Evidence
- one bounded adapter-backed load result exists
- one live user confirmation exists for selected-model load behavior
Closure Condition
This slice closes when:
- one selected MLX model can be loaded through the loader path
- runtime state reports ready or structured failure coherently
- one direct automated load smoke passes
- the repository user performs and confirms the live load test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P1.T3.S1 unless bounded remediation is required for the load path.
