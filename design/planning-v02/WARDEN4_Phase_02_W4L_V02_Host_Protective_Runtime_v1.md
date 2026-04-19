WARDEN4 Phase 02 W4L v0.2 Host Protective Runtime v1
Status: Active Planning Artifact Scope: Loader v0.2 host-protective hardening path
Objective
Upgrade the working W4L v0.1 runtime into a host-protective loader that admits loads conservatively, verifies reclaim, and contains backend instability without taking down the operator process.

Entry Gate
- W4L v0.1 baseline is working and closed
- `docs/W4L_V02_IMPLEMENTATION_SPEC.md` is the active execution source
- control contract remains on `:8787`
- compatibility bridge remains on `:8080`
- target host remains 16GB Apple Silicon macOS

Controlling Canon
- `/Users/kikbot/Documents/WARDEN4/WARDEN4-Local-LLM-Loader-Rebuild/README.md`
- `/Users/kikbot/Documents/WARDEN4/WARDEN4-Local-LLM-Loader-Rebuild/docs/W4L_V02_IMPLEMENTATION_SPEC.md`
- `/Users/kikbot/Documents/WARDEN4/WARDEN4-Local-LLM-Loader-Rebuild/docs/ARCHITECTURE.md`
- `/Users/kikbot/Documents/WARDEN4/WARDEN4-Local-LLM-Loader-Rebuild/docs/INTEGRATION_NOTES_FOR_PI_MONO.md`
- `/Users/kikbot/Documents/WARDEN4/WARDEN4-Local-LLM-Loader-Rebuild/docs/WEC_LOOP_EXECUTION_BACKLOG.md`

Tracks And Slice Register
Track 2.1 - Memory Budget Authority
- trace and evidence path:
  - one measurable memory source of truth
  - explicit ceiling and reserve constants
  - pre-spawn admission decision
- slices:
  - P2.T1.S1 - memory measurement and budget constants baseline
    - status: planned
  - P2.T1.S2 - admission gate before helper spawn
    - status: planned

Track 2.2 - Budget Verification And Reclaim
- trace and evidence path:
  - post-load ceiling verification
  - reset reclaim verification
  - operator-visible budget status
- slices:
  - P2.T2.S1 - post-load budget verification
    - status: planned
  - P2.T2.S2 - reclaim verification after reset
    - status: planned
  - P2.T2.S3 - budget reporting in status surfaces
    - status: planned

Track 2.3 - Supervision And Fail-Fast
- trace and evidence path:
  - supervisor-owned runtime state
  - crash detection
  - bounded restart window
  - fail-fast recovery gate
- slices:
  - P2.T3.S1 - supervisor extraction and crash accounting
    - status: planned
  - P2.T3.S2 - bounded restart and fail-fast policy
    - status: planned
  - P2.T3.S3 - compatibility bridge and operator recovery alignment
    - status: planned

Exit Gate
- unsafe loads are refused before helper spawn
- post-load over-budget state is detected and closed
- reset does not return healthy idle until reclaim is verified
- repeated helper instability enters `failed_fast`
- operator can see budget and failure state
- `pi-mono` receives coherent failure across admission and fail-fast paths

Live Test Gate
- no slice advances to the next PEM on automated checks alone
- each slice requires one live user test performed by the repository operator
- the next slice stays blocked until that live result is explicitly confirmed

Relationship To Other Planning Docs
- this phase is the execution control surface for W4L v0.2
- v0.1 planning artifacts remain historical baseline only
- the broader backlog remains in `docs/WEC_LOOP_EXECUTION_BACKLOG.md`
