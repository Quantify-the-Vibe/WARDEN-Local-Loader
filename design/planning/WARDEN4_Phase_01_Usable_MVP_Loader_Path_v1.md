WARDEN4 Phase 01 Usable MVP Loader Path v1
Status: Active Planning Artifact Scope: Loader MVP build order for one usable local-model path
Objective
Build the loader in bounded vertical slices so the subsystem becomes usable while it is being built.

Entry Gate
- loader subsystem canon is frozen for the current MVP
- local models root remains `/Users/kikbot/.models/mlx/`
- first client remains `pi-mono`

Controlling Canon
- `/Users/kikbot/Documents/WARDEN4/WARDEN-Model-Loader/README.md`
- `/Users/kikbot/Documents/WARDEN4/WARDEN-Model-Loader/docs/LOADER_IMPLEMENTATION_SPEC.md`
- `/Users/kikbot/Documents/WARDEN4/WARDEN-Model-Loader/docs/ARCHITECTURE.md`
- `/Users/kikbot/Documents/WARDEN4/WARDEN-Model-Loader/docs/INTEGRATION_NOTES_FOR_PI_MONO.md`
- `/Users/kikbot/Documents/WARDEN4/WARDEN-Model-Loader/docs/WEC_LOOP_EXECUTION_BACKLOG.md`

Tracks And Slice Register
Track 1.1 - Operator Surface And Discovery
- trace and evidence path:
  - launchable operator shell
  - visible controls
  - live model discovery
- slices:
  - P1.T1.S1 - operator shell bootstrap
    - status: planned
  - P1.T1.S2 - mlx model discovery and selection
    - status: planned

Track 1.2 - Runtime Load Path
- trace and evidence path:
  - bounded backend seam
  - selected-model load
  - coherent runtime state
- slices:
  - P1.T2.S1 - selected model load baseline
    - status: planned

Track 1.3 - Client Contract And Integration
- trace and evidence path:
  - local HTTP boundary
  - pi-mono connection
  - one prompt and one response
- slices:
  - P1.T3.S1 - local HTTP contract baseline
    - status: planned
  - P1.T3.S2 - pi-mono prompt response path
    - status: planned

Track 1.4 - Reuse And Recovery
- trace and evidence path:
  - minimal unload
  - minimal reset
  - repeatable reuse after live test
- slices:
  - P1.T4.S1 - minimal unload and reset path
    - status: planned

Exit Gate
- operator can launch the SwiftUI loader shell
- operator can see and select MLX models
- operator can load one model
- pi-mono can send one prompt through the loader and receive one response
- minimal unload/reset exists so the path can be reused during ongoing build work

Live Test Gate
- no slice advances to the next PEM on automated checks alone
- each slice requires one live user test performed by the repository operator
- the next slice stays blocked until that live result is explicitly confirmed

Relationship To Other Planning Docs
- this phase is the execution control surface for the loader MVP
- the broader backlog remains in `docs/WEC_LOOP_EXECUTION_BACKLOG.md`
