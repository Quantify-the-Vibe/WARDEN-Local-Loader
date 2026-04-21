import Dispatch
import Foundation
import Testing
@testable import LoaderShell

struct LoaderShellViewModelTests {
    @MainActor
    @Test
    func supervisorEntersFailedFastAfterCrashWindowExceeded() {
        var tick: TimeInterval = 0
        let supervisor = try! LoaderSupervisor(
            crashLimit: 2,
            crashWindow: 60,
            maxCrashEquivalentTimeoutSeconds: 20,
            now: {
                defer { tick += 1 }
                return Date(timeIntervalSince1970: tick)
            }
        )

        supervisor.handleRuntimeEvent(BackendRuntimeEvent.helperExitedUnexpectedly(pid: 1, terminationStatus: 9))
        #expect(supervisor.runtimeState == LoaderRuntimeState.failed)
        supervisor.handleRuntimeEvent(BackendRuntimeEvent.helperExitedUnexpectedly(pid: 2, terminationStatus: 9))
        #expect(supervisor.runtimeState == LoaderRuntimeState.failed)
        supervisor.handleRuntimeEvent(BackendRuntimeEvent.helperExitedUnexpectedly(pid: 3, terminationStatus: 9))

        #expect(supervisor.runtimeState == LoaderRuntimeState.failedFast)
        #expect(supervisor.isFailedFastActive == true)
        #expect(supervisor.statusPayload["failed_fast_active"] as? Bool == true)
    }

    @MainActor
    @Test
    func supervisorClearFailedFastReturnsToIdle() {
        let supervisor = try! LoaderSupervisor(
            crashLimit: 0,
            crashWindow: 60,
            maxCrashEquivalentTimeoutSeconds: 20,
            now: Date.init
        )
        supervisor.handleRuntimeEvent(BackendRuntimeEvent.helperExitedUnexpectedly(pid: 1, terminationStatus: 9))
        #expect(supervisor.runtimeState == LoaderRuntimeState.failedFast)

        supervisor.clearFailedFastForOperatorRecovery()

        #expect(supervisor.runtimeState == LoaderRuntimeState.idle)
        #expect(supervisor.isFailedFastActive == false)
    }

    @Test
    func admissionEvaluatorAllowsWithinEffectiveCeiling() {
        let evaluator = LoadAdmissionEvaluator(
            constants: .baseline,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
        )
        let snapshot = MemoryBudgetSnapshot(
            measurementSource: "mock_source",
            appPID: 111,
            helperPID: nil,
            appFootprintBytes: 512 * 1_024 * 1_024,
            helperFootprintBytes: 0,
            combinedFootprintBytes: 512 * 1_024 * 1_024,
            constants: .baseline
        )

        let decision = evaluator.evaluate(
            snapshot: snapshot,
            projectedModelCostBytes: 2 * 1_024 * 1_024 * 1_024
        )

        #expect(decision.result == "allowed")
        #expect(decision.reasonCode == nil)
    }

    @Test
    func admissionEvaluatorDeniesWhenCeilingExceeded() {
        let evaluator = LoadAdmissionEvaluator(
            constants: .baseline,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
        )
        let snapshot = MemoryBudgetSnapshot(
            measurementSource: "mock_source",
            appPID: 111,
            helperPID: nil,
            appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
            helperFootprintBytes: 0,
            combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
            constants: .baseline
        )

        let decision = evaluator.evaluate(
            snapshot: snapshot,
            projectedModelCostBytes: 11 * 1_024 * 1_024 * 1_024
        )

        #expect(decision.result == "denied")
        #expect(decision.reasonCode == "memory_ceiling_exceeded")
    }

    @Test
    func postLoadVerifierDeniesWhenMeasuredFootprintExceedsCeiling() {
        let evaluator = LoadAdmissionEvaluator(
            constants: .baseline,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
        )
        let snapshot = MemoryBudgetSnapshot(
            measurementSource: "mock_source",
            appPID: 111,
            helperPID: 222,
            appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
            helperFootprintBytes: 11 * 1_024 * 1_024 * 1_024,
            combinedFootprintBytes: 13 * 1_024 * 1_024 * 1_024,
            constants: .baseline
        )

        let decision = evaluator.evaluatePostLoad(snapshot: snapshot)

        #expect(decision.result == "over_budget")
        #expect(decision.reasonCode == "post_load_budget_verification_failed")
    }

    @Test
    func reclaimVerifierDeniesWhenMeasuredFootprintExceedsBaselinePlusSlack() {
        let evaluator = LoadAdmissionEvaluator(
            constants: .baseline,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
        )
        let snapshot = MemoryBudgetSnapshot(
            measurementSource: "mock_source",
            appPID: 111,
            helperPID: nil,
            appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
            helperFootprintBytes: 0,
            combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
            constants: .baseline
        )

        let decision = evaluator.evaluateReclaim(
            baselineFootprintBytes: 512 * 1_024 * 1_024,
            snapshot: snapshot
        )

        #expect(decision.result == "insufficient_reclaim")
        #expect(decision.reasonCode == "reclaim_verification_failed")
    }

    @MainActor
    @Test
    func statusPayloadIncludesBudgetSnapshot() async throws {
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )

        let payload = viewModel.httpStatusPayload()
        #expect(payload["memory_budget_status"] as? String == "Measurement ready.")
        let budget = payload["memory_budget"] as? [String: Any]
        #expect(budget?["measurement_source"] as? String == "mock_source")
        #expect(budget?["current_footprint_bytes"] as? UInt64 == 1_024)
        #expect(budget?["ceiling_bytes"] as? UInt64 == MemoryBudgetConstants.baseline.loaderMemoryCeilingBytes)
        let report = payload["budget_report"] as? [String: Any]
        #expect(report?["lifecycle_state"] as? String == "idle")
        #expect(report?["measurement_status"] as? String == "Measurement ready.")
        let supervisorState = payload["supervisor_state"] as? [String: Any]
        #expect(supervisorState?["runtime_state"] as? String == "idle")
        #expect(supervisorState?["crash_count"] as? Int == 0)
        #expect(supervisorState?["crash_window_count"] as? Int == 0)
        #expect(supervisorState?["failed_fast_active"] as? Bool == false)
    }

    @MainActor
    @Test
    func failedMeasurementSurfacesStructuredStatus() async throws {
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                error: ProcessMemoryMeasurementError.measurementUnavailable(pid: 999)
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )

        #expect(viewModel.memoryBudgetStatus == "Measurement failed.")
        #expect(viewModel.memoryBudgetSummary.contains("resident_size"))
        let payload = viewModel.httpStatusPayload()
        let budget = payload["memory_budget"] as? [String: Any]
        #expect(budget == nil)
    }

    @MainActor
    @Test
    func loadFailsClosedWhenMeasurementUnavailable() async throws {
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                error: ProcessMemoryMeasurementError.measurementUnavailable(pid: 999)
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()

        #expect(viewModel.status == .failed)
        #expect(viewModel.activeModelSummary.contains("memory_measurement_unavailable"))
        #expect(viewModel.admissionSummary.contains("memory_measurement_unavailable"))
    }

    @MainActor
    @Test
    func loadFailsClosedWhenProjectedTotalExceedsCeiling() async throws {
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 11 * 1_024 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()

        #expect(viewModel.status == .failed)
        #expect(viewModel.activeModelSummary.contains("memory_ceiling_exceeded"))
        #expect(viewModel.admissionSummary.contains("denied"))
    }

    @MainActor
    @Test
    func loadTerminatesHelperWhenPostLoadVerificationFails() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 512 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 512 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 512 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 512 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 512 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 512 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 11 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 13 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1 * 1_024 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()
        await fulfillment { backendLoader.shutdownCallCount == 1 }

        #expect(viewModel.status == .failed)
        #expect(viewModel.activeModelSummary.contains("post_load_budget_verification_failed"))
        #expect(viewModel.postLoadSummary.contains("over_budget"))
    }

    @MainActor
    @Test
    func loadReachesReadyWhenPostLoadVerificationPasses() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 512 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 1536 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 256 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()
        await fulfillment { viewModel.status == .ready }

        #expect(viewModel.postLoadSummary.contains("within_budget"))
        #expect(backendLoader.shutdownCallCount == 0)
    }

    @MainActor
    @Test
    func loadFailsClosedWhenPostLoadSettlementIsUnstable() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: OscillatingMemoryBudgetMonitor(
                low: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                high: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 4 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 6 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 256 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            postLoadSettlementSleep: { _ in },
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()
        await fulfillment { viewModel.status == .failed }

        #expect(backendLoader.shutdownCallCount == 1)
        #expect(viewModel.activeModelSummary.contains("post_load_budget_verification_failed"))
        #expect(viewModel.activeModelSummary.contains("did not stabilize"))
    }

    @MainActor
    @Test
    func observedBaselineProjectionCanDenyFutureAdmission() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 3 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    combinedFootprintBytes: 3 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 3 * 1_024 * 1_024,
                    combinedFootprintBytes: 3 * 1_024 * 1_024 * 1_024 + 3 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 10 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 10 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 128 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            postLoadSettlementSleep: { _ in },
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()
        await fulfillment { viewModel.status == .ready }
        #expect(backendLoader.loadCallCount == 1)

        viewModel.loadButtonPressed()

        #expect(viewModel.status == .failed)
        #expect(backendLoader.loadCallCount == 1)
        #expect(viewModel.activeModelSummary.contains("memory_ceiling_exceeded"))
        #expect(viewModel.admissionSummary.contains("Projection Confidence: max(filesystem, observed_baseline)"))
    }

    @MainActor
    @Test
    func generateRequestUsesPreAdmissionGateAndAllowsSafePrompt() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 512 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 1536 * 1_024 * 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        let response = await viewModel.httpGenerate(prompt: "hello")
        #expect(response.statusCode == 200)
        #expect(backendLoader.generateCallCount == 1)
        #expect(viewModel.admissionSummary.contains("Generate Admission"))
    }

    @MainActor
    @Test
    func overBudgetGenerateIsDeniedBeforeBackendCall() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 11 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 11 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        let response = await viewModel.httpGenerate(prompt: String(repeating: "x", count: 8_000))
        #expect(response.statusCode == 503)
        #expect(backendLoader.generateCallCount == 0)
        let payload = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(payload["error"] as? String == "generate_memory_ceiling_exceeded")
    }

    @MainActor
    @Test
    func overBudgetChatGenerateIsDeniedBeforeGenerateCall() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024 + 1 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 1 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 11 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 11 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            postLoadSettlementSleep: { _ in },
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        let chatResponse = await viewModel.httpOpenAIChatCompletions(bodyJSON: [
            "model": "mock",
            "messages": [["role": "user", "content": String(repeating: "y", count: 8_000)]],
        ])
        #expect(chatResponse.statusCode == 503)
        #expect(backendLoader.generateChatCallCount == 0)

        let payload = try #require(JSONSerialization.jsonObject(with: chatResponse.body) as? [String: Any])
        let error = try #require(payload["error"] as? [String: Any])
        #expect(error["type"] as? String == "generate_memory_ceiling_exceeded")
    }

    @MainActor
    @Test
    func resetReturnsIdleWhenReclaimVerificationPasses() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.resetButtonPressed()
        await fulfillment { viewModel.status == .idle }

        #expect(viewModel.reclaimSummary.contains("reclaimed"))
        #expect(viewModel.resetSummary.contains("reclaim verified"))
        #expect(backendLoader.shutdownCallCount == 1)
    }

    @MainActor
    @Test
    func resetFailsWhenReclaimVerificationFails() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.resetButtonPressed()
        await fulfillment { viewModel.status == .failed }

        #expect(viewModel.reclaimSummary.contains("insufficient_reclaim"))
        #expect(viewModel.activeModelSummary.contains("reclaim_verification_failed"))
        #expect(backendLoader.shutdownCallCount == 1)
    }

    @MainActor
    @Test
    func reclaimFailureProjectsDegradedLockedAndBlocksLoadReuse() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.resetButtonPressed()
        await fulfillment { viewModel.status == .failed }
        viewModel.loadButtonPressed()

        let statusPayload = viewModel.httpStatusPayload()
        #expect(statusPayload["runtime_state"] as? String == "degraded_locked")
        #expect(statusPayload["recovery_action"] as? String == "operator_reclaim_recovery_required")
        #expect(viewModel.budgetReportSummary.contains("Lifecycle: degraded_locked"))
        #expect(viewModel.admissionSummary.contains("reclaim_lock_active"))
        #expect(viewModel.activeModelSummary.contains("reclaim_lock_active"))
        #expect(backendLoader.loadCallCount == 0)
    }

    @MainActor
    @Test
    func explicitRecoveryResetClearsDegradedLockedProjection() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )

        viewModel.resetButtonPressed()
        await fulfillment { viewModel.status == .failed }
        #expect(viewModel.httpStatusPayload()["runtime_state"] as? String == "degraded_locked")

        viewModel.resetButtonPressed()
        await fulfillment { viewModel.status == .idle }

        let statusPayload = viewModel.httpStatusPayload()
        #expect(statusPayload["runtime_state"] as? String == "idle")
        #expect(statusPayload["recovery_action"] == nil)
        #expect(viewModel.reclaimSummary.contains("reclaimed"))
    }

    @MainActor
    @Test
    func budgetReportSummaryProjectsSharedStatusState() async throws {
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )

        #expect(viewModel.budgetReportSummary.contains("Lifecycle: idle"))
        #expect(viewModel.budgetReportSummary.contains("Measurement Source: mock_source"))
        #expect(viewModel.budgetReportSummary.contains("Admission: not_run"))
    }

    @MainActor
    @Test
    func helperCrashTransitionsSupervisorStateWithoutKillingViewModel() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 512 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 1536 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 256 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()
        await fulfillment { viewModel.status == .ready }
        backendLoader.simulateUnexpectedExit()
        await fulfillment { viewModel.status == .failed }

        #expect(viewModel.statusDetail.contains("helper crash detected"))
        #expect(viewModel.supervisorSummary.contains("Crash Count: 1"))
        #expect(viewModel.activeModelSummary.contains("helper_crashed"))
    }

    @MainActor
    @Test
    func timeoutRuntimeEventProjectsTimeoutClassificationInViewModel() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 256 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )

        backendLoader.simulateReadyTimeout()
        await fulfillment { viewModel.status == .failed }

        #expect(viewModel.statusDetail.contains("helper ready timeout classified"))
        #expect(viewModel.activeModelSummary.contains("helper_ready_timeout"))
        #expect(viewModel.supervisorSummary.contains("code=helper_ready_timeout"))
    }

    @MainActor
    @Test
    func automaticRestartUsesBoundedBackoffSchedule() async throws {
        let backendLoader = MockBackendLoader()
        let delayRecorder = DelayRecorder()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 256 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            restartSleep: { delay in
                await delayRecorder.record(delay)
            },
            autoRestartOnCrash: true,
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()
        await fulfillment { viewModel.status == .ready }
        #expect(backendLoader.loadCallCount == 1)

        backendLoader.simulateUnexpectedExit()
        await fulfillment { backendLoader.loadCallCount >= 2 && viewModel.status == .ready }
        backendLoader.simulateUnexpectedExit()
        await fulfillment { backendLoader.loadCallCount >= 3 && viewModel.status == .ready }

        let observedDelays = await delayRecorder.snapshot()
        #expect(observedDelays.count >= 2)
        #expect(Int(observedDelays[0]) == 2)
        #expect(Int(observedDelays[1]) == 4)
    }

    @MainActor
    @Test
    func automaticRestartStopsWhenFailedFastIsActive() async throws {
        let backendLoader = MockBackendLoader()
        let delayRecorder = DelayRecorder()
        let supervisor = try! LoaderSupervisor(
            crashLimit: 0,
            crashWindow: 60,
            maxCrashEquivalentTimeoutSeconds: 20,
            now: Date.init
        )
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            supervisor: supervisor,
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 256 * 1_024 * 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            restartSleep: { delay in
                await delayRecorder.record(delay)
            },
            autoRestartOnCrash: true,
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()
        await fulfillment { viewModel.status == .ready }
        backendLoader.simulateUnexpectedExit()
        await fulfillment { viewModel.status == .failedFast }

        #expect(backendLoader.loadCallCount == 1)
        let observedDelays = await delayRecorder.snapshot()
        #expect(observedDelays.isEmpty)
    }

    @MainActor
    @Test
    func loadAdmissionBlockedWhileFailedFastIsActive() async throws {
        let supervisor = try! LoaderSupervisor(
            crashLimit: 0,
            crashWindow: 60,
            maxCrashEquivalentTimeoutSeconds: 20,
            now: Date.init
        )
        supervisor.handleRuntimeEvent(BackendRuntimeEvent.helperExitedUnexpectedly(pid: 1, terminationStatus: 9))
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            supervisor: supervisor,
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]
        viewModel.selectedModelID = "mock"

        viewModel.loadButtonPressed()

        #expect(viewModel.status == LoaderRuntimeState.failedFast)
        #expect(viewModel.activeModelSummary.contains("failed_fast_active"))
        #expect(viewModel.admissionSummary.contains("failed_fast_active"))
    }

    @MainActor
    @Test
    func resetClearsFailedFastAndReturnsIdleWhenReclaimPasses() async throws {
        let supervisor = try! LoaderSupervisor(
            crashLimit: 0,
            crashWindow: 60,
            maxCrashEquivalentTimeoutSeconds: 20,
            now: Date.init
        )
        supervisor.handleRuntimeEvent(BackendRuntimeEvent.helperExitedUnexpectedly(pid: 1, terminationStatus: 9))
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            supervisor: supervisor,
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 256 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 256 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )

        viewModel.resetButtonPressed()
        await fulfillment { viewModel.status == LoaderRuntimeState.idle }

        #expect(viewModel.status != LoaderRuntimeState.failedFast)
        #expect(viewModel.reclaimSummary.contains("reclaimed"))
        #expect(viewModel.supervisorSummary.contains("Lifecycle: idle"))
    }

    @MainActor
    @Test
    func openAIBridgeDefaultIsTranslationOnlyAndRequiresExplicitLoad() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: false,
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]

        let response = await viewModel.httpOpenAIChatCompletions(bodyJSON: [
            "model": "mock",
            "messages": [["role": "user", "content": "hello"]],
        ])

        let payload = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let error = try #require(payload["error"] as? [String: Any])
        #expect(response.statusCode == 503)
        #expect(error["type"] as? String == "explicit_load_required")
        #expect(backendLoader.loadCallCount == 0)
        #expect(backendLoader.generateChatCallCount == 0)
    }

    @MainActor
    @Test
    func openAIBridgeLegacyAutoloadCanBeEnabledByFlag() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024 + 1 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 1 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            postLoadSettlementSleep: { _ in },
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]

        let response = await viewModel.httpOpenAIChatCompletions(bodyJSON: [
            "model": "mock",
            "messages": [["role": "user", "content": "hello"]],
        ])

        #expect(response.statusCode == 200)
        #expect(backendLoader.loadCallCount == 1)
        #expect(backendLoader.generateChatCallCount == 1)
        #expect(backendLoader.lastGenerateChatMaxTokens == 2048)
        let firstMessage = try #require(backendLoader.lastGenerateChatMessages.first)
        #expect(firstMessage["role"] == "system")
        #expect((firstMessage["content"] ?? "").contains("Runtime capability boundary"))
    }

    @MainActor
    @Test
    func openAIBridgeForwardsRequestedMaxCompletionTokens() async throws {
        let backendLoader = MockBackendLoader()
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024 + 1 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 1 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            postLoadSettlementSleep: { _ in },
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]

        let response = await viewModel.httpOpenAIChatCompletions(bodyJSON: [
            "model": "mock",
            "messages": [["role": "user", "content": "hello"]],
            "max_completion_tokens": 4096,
        ])

        #expect(response.statusCode == 200)
        #expect(backendLoader.generateChatCallCount == 1)
        #expect(backendLoader.lastGenerateChatMaxTokens == 4096)
    }

    @MainActor
    @Test
    func openAIBridgeLengthFinishReasonIncludesContinuationHint() async throws {
        let backendLoader = MockBackendLoader()
        backendLoader.chatResult = BackendChatGenerateResult(
            text: "partial output",
            finishReason: "length",
            promptTokens: 120,
            completionTokens: 4096
        )
        let viewModel = LoaderShellViewModel(
            backendLoader: backendLoader,
            piMonoLauncher: .default(),
            memoryBudgetMonitor: SequencedMemoryBudgetMonitor(snapshots: [
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024 + 1 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 1 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024 + 2 * 1_024 * 1_024,
                    constants: .baseline
                ),
                MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: 222,
                    appFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    helperFootprintBytes: 1 * 1_024 * 1_024 * 1_024,
                    combinedFootprintBytes: 2 * 1_024 * 1_024 * 1_024,
                    constants: .baseline
                ),
            ]),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            postLoadSettlementSleep: { _ in },
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]

        let response = await viewModel.httpOpenAIChatCompletions(bodyJSON: [
            "model": "mock",
            "messages": [["role": "user", "content": "Tell me a long story."]],
            "max_tokens": 4096,
        ])

        #expect(response.statusCode == 200)
        let payload = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let choices = try #require(payload["choices"] as? [[String: Any]])
        let firstChoice = try #require(choices.first)
        #expect(firstChoice["finish_reason"] as? String == "length")
        let usage = try #require(payload["usage"] as? [String: Any])
        #expect(usage["completion_tokens"] as? Int == 4096)
        let w4l = try #require(payload["w4l"] as? [String: Any])
        #expect(w4l["continuation_available"] as? Bool == true)
    }

    @MainActor
    @Test
    func openAICompatFailureMapsFailedFastWithRecoveryAction() async throws {
        let supervisor = try! LoaderSupervisor(
            crashLimit: 0,
            crashWindow: 60,
            maxCrashEquivalentTimeoutSeconds: 20,
            now: Date.init
        )
        supervisor.handleRuntimeEvent(BackendRuntimeEvent.helperExitedUnexpectedly(pid: 1, terminationStatus: 9))
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            supervisor: supervisor,
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            bridgeAutoLoadEnabled: true,
            startHTTPServers: false
        )
        viewModel.availableModels = [
            LoaderShellViewModel.ModelRecord(id: "mock", displayName: "mock", localPath: "/tmp/mock")
        ]

        let response = await viewModel.httpOpenAIChatCompletions(bodyJSON: [
            "model": "mock",
            "messages": [["role": "user", "content": "hello"]],
        ])

        let payload = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let error = try #require(payload["error"] as? [String: Any])
        #expect(response.statusCode == 503)
        #expect(error["type"] as? String == "failed_fast_active")
        #expect(error["loader_state"] as? String == "failed_fast")
        #expect(error["recovery_action"] as? String == "operator_reset_required")
    }

    @MainActor
    @Test
    func statusPayloadProjectsRecoveryActionWhenFailedFastActive() async throws {
        let supervisor = try! LoaderSupervisor(
            crashLimit: 0,
            crashWindow: 60,
            maxCrashEquivalentTimeoutSeconds: 20,
            now: Date.init
        )
        supervisor.handleRuntimeEvent(BackendRuntimeEvent.helperExitedUnexpectedly(pid: 1, terminationStatus: 9))
        let viewModel = LoaderShellViewModel(
            backendLoader: MockBackendLoader(),
            piMonoLauncher: .default(),
            supervisor: supervisor,
            memoryBudgetMonitor: MockMemoryBudgetMonitor(
                snapshot: MemoryBudgetSnapshot(
                    measurementSource: "mock_source",
                    appPID: 111,
                    helperPID: nil,
                    appFootprintBytes: 1_024,
                    helperFootprintBytes: 0,
                    combinedFootprintBytes: 1_024,
                    constants: .baseline
                )
            ),
            modelCostEstimator: MockModelCostEstimator(estimatedBytes: 1_024),
            admissionEvaluator: LoadAdmissionEvaluator(
                constants: .baseline,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            ),
            startHTTPServers: false
        )

        let payload = viewModel.httpStatusPayload()
        #expect(payload["runtime_state"] as? String == "failed_fast")
        #expect(payload["recovery_action"] as? String == "operator_reset_required")
        #expect((payload["recovery_message"] as? String)?.contains("Operator reset is required") == true)
        let report = try #require(payload["budget_report"] as? [String: Any])
        #expect(report["lifecycle_state"] as? String == "failed_fast")
        #expect(report["recovery_action"] as? String == "operator_reset_required")
    }
}

private final class MockBackendLoader: BackendLoader {
    var runtimeEventHandler: ((BackendRuntimeEvent) -> Void)?
    private(set) var shutdownCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var generateCallCount = 0
    private(set) var generateChatCallCount = 0
    private(set) var lastGenerateChatMaxTokens: Int?
    private(set) var lastGenerateChatMessages: [[String: String]] = []
    var chatResult = BackendChatGenerateResult(
        text: "",
        finishReason: "stop",
        promptTokens: 0,
        completionTokens: 0
    )

    func load(model: LoaderShellViewModel.ModelRecord) async throws -> BackendReadyReport {
        loadCallCount += 1
        return BackendReadyReport(
            modelID: model.id,
            modelPath: model.localPath,
            pidText: "222",
            transport: "mock",
            note: "mock"
        )
    }

    func generate(prompt: String) async throws -> String {
        generateCallCount += 1
        return ""
    }

    func generateChat(messages: [[String : String]], maxTokens: Int?) async throws -> BackendChatGenerateResult {
        generateChatCallCount += 1
        lastGenerateChatMaxTokens = maxTokens
        lastGenerateChatMessages = messages
        return chatResult
    }
    func shutdown() async { shutdownCallCount += 1 }
    func activeHelperPID() -> Int32? { 222 }

    func simulateUnexpectedExit() {
        runtimeEventHandler?(.helperExitedUnexpectedly(pid: 222, terminationStatus: 9))
    }

    func simulateReadyTimeout() {
        runtimeEventHandler?(.helperReadyTimeout(timeoutSeconds: 120))
    }
}

private struct MockMemoryBudgetMonitor: MemoryBudgetMonitoring {
    let snapshotValue: MemoryBudgetSnapshot?
    let errorValue: Error?

    init(snapshot: MemoryBudgetSnapshot) {
        self.snapshotValue = snapshot
        self.errorValue = nil
    }

    init(error: Error) {
        self.snapshotValue = nil
        self.errorValue = error
    }

    func snapshot(helperPID: Int32?) throws -> MemoryBudgetSnapshot {
        if let errorValue {
            throw errorValue
        }
        return snapshotValue!
    }
}

private final class SequencedMemoryBudgetMonitor: MemoryBudgetMonitoring, @unchecked Sendable {
    private var snapshots: [MemoryBudgetSnapshot]
    private var index = 0

    init(snapshots: [MemoryBudgetSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot(helperPID: Int32?) throws -> MemoryBudgetSnapshot {
        let currentIndex = min(index, snapshots.count - 1)
        let snapshot = snapshots[currentIndex]
        index += 1
        return snapshot
    }
}

private final class OscillatingMemoryBudgetMonitor: MemoryBudgetMonitoring, @unchecked Sendable {
    private let low: MemoryBudgetSnapshot
    private let high: MemoryBudgetSnapshot
    private var nextHigh = false

    init(low: MemoryBudgetSnapshot, high: MemoryBudgetSnapshot) {
        self.low = low
        self.high = high
    }

    func snapshot(helperPID: Int32?) throws -> MemoryBudgetSnapshot {
        defer { nextHigh.toggle() }
        return nextHigh ? high : low
    }
}

private struct MockModelCostEstimator: ModelCostEstimating {
    let estimatedBytes: UInt64

    func estimatedModelBytes(at modelPath: String) throws -> UInt64 {
        estimatedBytes
    }
}

private actor DelayRecorder {
    private var delays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        delays.append(delay)
    }

    func snapshot() -> [TimeInterval] {
        delays
    }
}

@MainActor
private func fulfillment(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return
        }
        await Task.yield()
    }
}
