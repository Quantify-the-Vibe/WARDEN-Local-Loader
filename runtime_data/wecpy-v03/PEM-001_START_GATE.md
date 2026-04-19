# PEM-001 Start Gate

Status: ready to begin coding
PEM: `PEM-001-timeout-classification-and-crash-window-invariants`
Authority source: `runtime_data/wecpy-v03/authoritative-pems/PEM-001-timeout-classification-and-crash-window-invariants.md`

## Locked Objective

Implement only:

- timeout classes represented as crash-equivalent events
- crash-window invariant enforcement for timeout-compatible policy math

Do not include restart backoff execution in this slice.
That belongs to `PEM-002`.

## Resolved Target Files

Primary implementation targets:

- `Sources/LoaderShell/BackendLoader.swift`
- `Sources/LoaderShell/MLXBackendLoader.swift`
- `Sources/LoaderShell/LoaderSupervisor.swift`
- `Sources/LoaderShell/LoaderShellViewModel.swift`

Primary test targets:

- `Tests/LoaderShellTests/LoaderShellViewModelTests.swift`
- `Tests/LoaderShellTests/LoaderSupervisorTests.swift` (new)

## Required Design Decisions For This Slice

1. Add timeout-class runtime events
- Introduce explicit runtime events for:
  - helper ready timeout
  - helper generate timeout
- Keep helper process exit event unchanged.

2. Enforce crash-window invariant in supervisor constructor
- Enforce:
  - `crashWindowSeconds >= (maxCrashEquivalentTimeoutSeconds * 3)`
- Reject invalid configuration early (initializer precondition or throwing init).

3. Map timeout failures into supervisor
- Convert backend timeout failures into timeout runtime events.
- Ensure timeout events increment crash-equivalent window accounting.

4. Preserve current authority behavior
- `failed_fast` policy remains bounded and fail-closed.
- No implicit bridge authority changes in this slice.

## Automated Test Plan (Must Pass)

1. Timeout mapping test
- Assert helper-ready timeout produces timeout-class runtime event.
- Assert helper-generate timeout produces timeout-class runtime event.

2. Crash-window invariant test
- Assert invalid `crashWindow` to timeout ratio is rejected.
- Assert valid ratio initializes successfully.

3. Crash-equivalent accounting test
- Assert timeout-class events contribute to window count.
- Assert repeated timeout-class events can drive `failed_fast` transition.

Baseline gate:

- `swift test --parallel` must remain green for full suite.

## Live Test Protocol (User Gate)

Run one live timeout visibility test before advancing:

1. Start loader app.
2. Trigger a timeout-classified failure path.
3. Verify timeout-classified failure is visible in:
- shell status output
- bridge error payload
4. Confirm pass in thread explicitly:
- `PEM-001 live test passed`

Do not start `PEM-002` until this explicit confirmation exists.

## Pre-Coding Command Set

- `git checkout -b pem-001-timeout-classification-and-crash-window-invariants`
- `swift test --parallel`
- `./tools/ci_smoke_status.sh` (optional local runtime probe)

## Exit Criteria

PEM-001 is complete only when:

- all PEM acceptance criteria are met
- automated tests above pass
- user live test confirmation is recorded
- next slice remains blocked until that confirmation
