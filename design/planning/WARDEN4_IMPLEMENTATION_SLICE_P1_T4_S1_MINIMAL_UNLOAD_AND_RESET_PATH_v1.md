WARDEN4 Implementation Slice P1.T4.S1 Minimal Unload And Reset Path v1
Status: Planned Slice Class: Phase-local execution Write Scope: Minimal unload/reset surfaces and directly supporting docs/tests for P1.T4.S1
Objective
Execute P1.T4.S1 inside Phase 01 Usable MVP Loader Path without expanding beyond one bounded implementation claim.
Claim
Provide one minimal unload/reset path so the MVP can be reused during ongoing build work.
Parent Phase
- `WARDEN4_Phase_01_Usable_MVP_Loader_Path_v1.md`
Parent Track
- Reuse And Recovery
Changes In Scope
- add one bounded unload control
- add one bounded reset control
- return the operator shell to a reusable non-serving state
- update directly dependent docs or tests inside the declared write scope only
Explicit Out Of Scope
- reclaim verification policy
- cooldown policy
- advanced failure recovery
- multi-model switching policy
Verification
- bounded unload/reset smoke after one successful model load
- repository user live test:
  - load one real model
  - trigger unload or reset
  - confirm the shell returns to a reusable state
  - confirm the next load can be attempted cleanly
Evidence
- one bounded unload/reset smoke result exists
- one live user confirmation exists for reuse after reset
Closure Condition
This slice closes when:
- one minimal unload or reset path works after a successful load
- the shell returns to a reusable non-serving state
- one direct unload/reset smoke passes
- the repository user performs and confirms the live reuse test
- follow-on work remains blocked until that live confirmation is recorded
Follow-On
Open the next admitted post-MVP hardening slice only after the live reuse gate is confirmed.
