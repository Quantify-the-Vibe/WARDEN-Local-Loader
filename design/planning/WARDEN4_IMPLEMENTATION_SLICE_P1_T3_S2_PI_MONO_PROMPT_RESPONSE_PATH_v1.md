WARDEN4 Implementation Slice P1.T3.S2 pi-mono Prompt Response Path v1
Status: Planned Slice Class: Phase-local execution Write Scope: pi-mono integration surfaces and directly supporting docs/tests for P1.T3.S2
Objective
Execute P1.T3.S2 inside Phase 01 Usable MVP Loader Path without expanding beyond one bounded implementation claim.
Claim
Allow pi-mono to connect through the loader boundary, send one prompt, and receive one response from the active MLX model.
Parent Phase
- `WARDEN4_Phase_01_Usable_MVP_Loader_Path_v1.md`
Parent Track
- Client Contract And Integration
Changes In Scope
- implement the bounded pi-mono to loader connection path
- support one prompt and one response over the admitted local HTTP surface
- update directly dependent docs or tests inside the declared write scope only
Explicit Out Of Scope
- streaming
- transcript persistence
- richer orchestration features
- non-MLX backends
Verification
- bounded end-to-end smoke from pi-mono through the loader to the active model
- repository user live test:
  - load one real model
  - connect pi-mono
  - send one prompt
  - confirm one response returns through the loader path
Evidence
- one bounded end-to-end integration result exists
- one live user confirmation exists for prompt/response success
Closure Condition
This slice closes when:
- pi-mono uses the loader boundary rather than backend internals
- one prompt can be sent and one response can be received
- one direct end-to-end smoke passes
- the repository user performs and confirms the live prompt/response test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P1.T4.S1 unless bounded remediation is required for the integration path.
