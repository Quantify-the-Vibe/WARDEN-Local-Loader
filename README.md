# WARDEN4 Local LLM Loader Rebuild

Local inference loader subsystem inside:

- `/Users/kikbot/Documents/WARDEN4/WARDEN4-Rebuild/`

This repo is not the whole WARDEN4 product.
It is one bounded subsystem responsible for local model runtime control.

## Purpose

Current purpose:

- keep one local model runtime boundary outside client apps
- provide a small operator-facing macOS control surface
- let `pi-mono` connect through the loader instead of calling backend internals directly

Next purpose:

- define the next bounded post-v0.2 upgrade set without reopening the closed v0.2 slice corpus

## Working Frame

- loader is a subsystem, not a chat product
- loader owns local runtime lifecycle
- `pi-mono` is the first client, not the authority model
- backend seam must stay generic
- MLX is the first implemented backend only
- v0.2 host-protective runtime is complete and closed
- v0.3 planning should stay bounded and avoid ad hoc feature drift

## Current Implemented State

Implemented now:

- SwiftUI macOS operator app
- model discovery from `/Users/kikbot/.models/mlx/`
- one active model lane
- `BackendLoader` seam
- `MLXBackendLoader` first concrete adapter
- persistent Python MLX helper
- control HTTP server on `:8787`
- OpenAI-compatible bridge on `:8080/v1/*`
- `pi-mono` connection through the bridge
- reset path
- packaged macOS `.app` bundle under `dist/`
- memory budget measurement baseline
- explicit budget constants
- pre-spawn admission gate
- post-load budget verification
- reclaim verification after reset
- supervisor-owned crash accounting
- bounded fail-fast policy
- compatibility-bridge recovery mapping

Not implemented now:

- automatic restart backoff execution
- helper protocol timeout supervision
- tighter MLX memory-cost estimation
- second backend validation
- explicitly admitted v0.3 corpus

## Canon

Closed baseline chain:

- `docs/W4L_V02_IMPLEMENTATION_SPEC.md`
- `docs/LOADER_IMPLEMENTATION_SPEC.md`
- `docs/ARCHITECTURE.md`
- `docs/INTEGRATION_NOTES_FOR_PI_MONO.md`
- `docs/WEC_LOOP_EXECUTION_BACKLOG.md`

Next planning source:

- `docs/W4L_V03_PLANNING_SPEC.md`

Active execution source:

- `docs/W4L_V03_IMPLEMENTATION_SPEC.md`

The v0.2 docs define the closed implemented baseline.
The v0.3 implementation spec is the active authority source for next corpus generation.
These docs are not themselves the PEM corpus.

Archived historical notes not in active canon:

- `docs/MEMORY_MANAGEMENT.md`
- `docs/FAULT_TOLERANCE.md`

Those files are retained for provenance only and should not be used as current design-review input.

## Operating Constraints

- host target: Apple Silicon macOS machine with 16GB unified memory
- loader must protect the host first
- target operating ceiling for loader-managed memory is 12GB
- if safe admission cannot be proven, the loader must fail closed
- present-tense implementation claims must stay aligned with code

## Security Controls

Implemented security controls:

- local HTTP listener constrained to loopback endpoint intent (`127.0.0.1`)
- request-body hard limit and timeout guards on inbound HTTP parsing
- optional route authorization for control/generation routes via `W4L_API_TOKEN`
- default-redacted diagnostics in status payloads
  - enable full diagnostics only with `W4L_EXPOSE_DIAGNOSTICS=1`
- helper script path integrity checks
  - optional explicit path via `W4L_HELPER_SCRIPT_PATH`
  - refuses helper script symlinks and world-writable script files

Recommended operator setup:

- generate local API token:
  - `./tools/setup_loader_token.sh`
- launch app from terminal so token env is applied:
  - `./run-loader-app.sh`
- `run-loader-app.sh` auto-loads `.env.local` when present

Authenticated route usage:

- protected routes:
  - `POST /load`
  - `POST /generate`
  - `POST /reset`
  - `POST /v1/chat/completions`
- compatibility discovery route (not protected):
  - `GET /v1/models`
- accepted auth headers:
  - `Authorization: Bearer <W4L_API_TOKEN>`
  - `X-Loader-Token: <W4L_API_TOKEN>`
- failed auth returns:
  - `401 Unauthorized`
  - `WWW-Authenticate: Bearer realm="W4L Loader", charset="UTF-8"`

## Launch

Build and launch the packaged app:

- `cd /Users/kikbot/Documents/WARDEN4/WARDEN4-Local-LLM-Loader-Rebuild && ./run-loader-app.sh`

Direct app path:

- `/Users/kikbot/Documents/WARDEN4/WARDEN4-Local-LLM-Loader-Rebuild/dist/LoaderShell.app`

## CI/CD

GitHub Actions now defines two macOS pipelines:

- `ci` workflow:
  - trigger: pull requests, pushes to `main`/`master`, and manual `workflow_dispatch`
  - cancel-in-progress enabled per ref
  - runs tests with code coverage export
  - builds launchable unsigned `.app`
  - runs smoke probe against `GET http://127.0.0.1:8787/status`
  - uploads artifacts:
    - `LoaderShell-<ci-tag>-macos.app.zip`
    - `LoaderShell-<ci-tag>-macos` (raw executable)
    - `SHA256SUMS.txt`
    - `coverage-summary.txt`
    - `coverage.lcov`
    - `default.profdata`

- `release` workflow:
  - trigger: tag push matching `v*` (example: `v0.3.1`) or manual `workflow_dispatch` with existing tag input
  - cancel-in-progress enabled per ref
  - runs tests and build
  - creates GitHub Release and uploads the same unsigned artifact set for the tag

Local equivalent packaging command:

- `./tools/package_macos_artifacts.sh v0.0.0-local`

Local CI helper commands:

- `./tools/ci_coverage_export.sh`
- `./tools/ci_smoke_status.sh`

Launch from artifact after download:

- app bundle: unzip `LoaderShell-<tag>-macos.app.zip`, then `open LoaderShell.app`
- raw binary: `chmod +x LoaderShell-<tag>-macos && ./LoaderShell-<tag>-macos`

## v0.2 Closure

Closed planning root:

- `design/planning-v02/`

Closed execution corpus:

- `runtime_data/wecpy/authoritative-pems/`

Closed PEM set:

- `PEM-001` - memory measurement and budget constants baseline
- `PEM-002` - admission gate before helper spawn
- `PEM-003` - post-load budget verification
- `PEM-004` - reclaim verification after reset
- `PEM-005` - budget reporting in status surfaces
- `PEM-006` - supervisor extraction and crash accounting
- `PEM-007` - bounded restart and fail-fast policy
- `PEM-008` - compatibility bridge and operator recovery alignment

Closed phase result:

- unsafe loads fail closed
- over-budget post-load state is terminated
- reset returns healthy `idle` only after reclaim verification passes
- helper crash does not kill the operator app
- repeated instability enters `failed_fast`
- operator shell and `pi-mono` now receive aligned recovery semantics

## v0.3 Planning Direction

Lowest-risk candidate themes:

- real restart backoff execution
- helper protocol timeout supervision
- tighter MLX memory-cost estimation
- operator-visible degraded-mode UX
- second adapter seam validation without changing authority boundaries

## Review Corpus

Approved review corpus copy:

- `design/review-corpus-v03/`

This folder should contain only the current review-approved design corpus and an exclusion manifest.

## WEC-Py v0.3 Corpus

Generated v0.3 WEC-Py execution artifacts are isolated at:

- `runtime_data/wecpy-v03/`

This keeps v0.2 execution artifacts in `runtime_data/wecpy/` unchanged.
