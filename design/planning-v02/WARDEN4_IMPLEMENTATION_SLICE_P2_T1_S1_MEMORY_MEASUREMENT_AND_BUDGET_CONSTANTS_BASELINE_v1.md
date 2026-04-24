WARDEN4 Implementation Slice P2.T1.S1 Memory Measurement And Budget Constants Baseline v1
Status: Planned Slice Class: Phase-local execution Write Scope: Memory measurement boundary, budget constants, and directly supporting docs/tests for P2.T1.S1
Objective
Execute P2.T1.S1 inside Phase 02 WML v0.2 Host Protective Runtime without expanding beyond one bounded implementation claim.
Claim
Define one measurable memory source of truth for loader-owned processes and expose explicit budget constants that the rest of v0.2 can consume.
Parent Phase
- `WARDEN4_Phase_02_WML_V02_Host_Protective_Runtime_v1.md`
Parent Track
- Memory Budget Authority
Changes In Scope
- select and implement one primary loader-owned memory measurement path
- define explicit ceiling and reserve constants in code
- expose enough bounded state so later slices can inspect the measurement result
- update directly supporting docs or tests inside the declared write scope only
Explicit Out Of Scope
- load refusal before helper spawn
- post-load enforcement
- reclaim verification
- restart or fail-fast behavior
Verification
- automated test for the chosen measurement path
- automated test that explicit budget constants are surfaced coherently
- repository user live test:
  - confirm the operator surface exposes a visible budget summary or measurement status
  - confirm the app remains usable while showing the new budget data
Evidence
- one bounded measurement source exists
- explicit constants exist for ceiling and reserves
- one live user confirmation exists for budget visibility
Closure Condition
This slice closes when:
- the code has one admitted memory source of truth for loader-owned processes
- explicit budget constants are visible in code and runtime state
- one direct automated measurement check passes
- one direct automated budget-surface check passes
- the repository user performs and confirms the live budget-visibility test
- the next slice remains blocked until that live confirmation is recorded
Follow-On
Follow P2.T1.S2 unless the chosen measurement path proves unreliable and requires bounded remediation first.
