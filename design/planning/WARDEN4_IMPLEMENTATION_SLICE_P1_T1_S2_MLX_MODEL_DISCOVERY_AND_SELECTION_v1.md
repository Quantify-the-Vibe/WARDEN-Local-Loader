WARDEN4 Implementation Slice P1.T1.S2 MLX Model Discovery And Selection v1
Status: Planned Slice Class: Phase-local execution Write Scope: Model discovery surfaces and directly supporting docs/tests for P1.T1.S2
Objective
Execute P1.T1.S2 inside Phase 01 Usable MVP Loader Path without expanding beyond one bounded implementation claim.
Claim
Populate the operator model selector from `/Users/kikbot/.models/mlx/` and allow one explicit model selection.
Parent Phase
- `WARDEN4_Phase_01_Usable_MVP_Loader_Path_v1.md`
Parent Track
- Operator Surface And Discovery
Changes In Scope
- implement bounded MLX model discovery from the admitted local root
- bind discovered model records into the selector
- update directly dependent docs or tests inside the declared write scope only
Explicit Out Of Scope
- model loading
- backend process lifetime
- HTTP endpoints
- pi-mono integration
Verification
- `swift build`
- one bounded discovery check against `/Users/kikbot/.models/mlx/`
- repository user live test:
  - open the shell
  - confirm the selector lists real local MLX model entries
  - confirm one entry can be selected
Evidence
- one bounded discovery result exists against the admitted model root
- one live user confirmation exists for model listing and selection
Closure Condition
This slice closes when:
- the selector is populated from `/Users/kikbot/.models/mlx/`
- one explicit model can be selected
- one direct automated build or discovery check passes
- the repository user performs and confirms the live discovery test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P1.T2.S1 unless bounded remediation is required for discovery correctness.
