WARDEN4 Implementation Slice P1.T3.S1 Local HTTP Contract Baseline v1
Status: Planned Slice Class: Phase-local execution Write Scope: Local HTTP contract surfaces and directly supporting docs/tests for P1.T3.S1
Objective
Execute P1.T3.S1 inside Phase 01 Usable MVP Loader Path without expanding beyond one bounded implementation claim.
Claim
Expose the bounded local HTTP contract for status, list-models, load, and generate without widening the public surface.
Parent Phase
- `WARDEN4_Phase_01_Usable_MVP_Loader_Path_v1.md`
Parent Track
- Client Contract And Integration
Changes In Scope
- implement one bounded local HTTP/JSON surface
- bind status, list-models, load, and generate to the loader runtime
- update directly dependent docs or tests inside the declared write scope only
Explicit Out Of Scope
- streaming
- unload/reset
- multi-client concurrency policy
- broader transport support
Verification
- `swift build`
- bounded local HTTP smoke for status, list-models, load, and generate
- repository user live test:
  - confirm the operator shell remains usable while the HTTP surface is active
  - confirm one local request path can be exercised without crashing the shell
Evidence
- one bounded HTTP smoke result exists
- one live user confirmation exists for shell stability during HTTP use
Closure Condition
This slice closes when:
- the bounded HTTP contract exists for status, list-models, load, and generate
- one direct automated HTTP smoke passes
- the repository user performs and confirms the live shell-stability test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P1.T3.S2 unless bounded remediation is required for contract correctness.
