import Foundation

@MainActor
@Observable
final class LoaderShellViewModel: LocalHTTPServerDelegate {
    struct ModelRecord: Identifiable, Equatable {
        let id: String
        let displayName: String
        let localPath: String
    }

    typealias RuntimeStatus = LoaderRuntimeState

    private static let modelRoot = "/Users/kikbot/.models/mlx"
    private static let controlPort: UInt16 = 8787
    private static let openAICompatPort: UInt16 = 8080
    private let backendLoader: BackendLoader
    private let piMonoLauncher: PiMonoLauncher
    private let supervisor: LoaderSupervisor
    private let memoryBudgetMonitor: any MemoryBudgetMonitoring
    private let modelCostEstimator: any ModelCostEstimating
    private let admissionEvaluator: LoadAdmissionEvaluator
    private var controlHTTPServer: LocalHTTPServer?
    private var openAICompatHTTPServer: LocalHTTPServer?

    let shellTitle = "WARDEN4 Local Loader"
    let shellSubtitle = "MVP operator shell for the local model loader"

    var availableModels: [ModelRecord] = []
    var selectedModelID: String?
    var statusDetail = "PEM-002 discovery active. Scanning the admitted MLX model root."
    var discoverySummary = "No models loaded yet."
    var activeModelSummary = "No model loaded."
    var serverSummary = "HTTP server not started."
    var generationSummary = "Prompt/response path is ready once one model is loaded."
    var piMonoSummary = "pi-mono launch path not attempted."
    var resetSummary = "Reset path not attempted."
    var memoryBudgetSummary = "Memory budget snapshot not measured yet."
    var memoryBudgetStatus = "Measurement pending."
    var admissionSummary = "Admission not evaluated yet."
    var postLoadSummary = "Post-load verification not run yet."
    var reclaimSummary = "Reclaim verification not run yet."
    private var lastMemoryBudgetSnapshot: MemoryBudgetSnapshot?
    private var lastAdmissionDecision: AdmissionDecision?
    private var lastPostLoadVerification: PostLoadVerificationDecision?
    private var lastReclaimVerification: ReclaimVerificationDecision?
    private var reusableIdleBaselineBytes: UInt64?

    init(
        backendLoader: BackendLoader = MLXBackendLoader(),
        piMonoLauncher: PiMonoLauncher = .default(),
        supervisor: LoaderSupervisor = LoaderSupervisor(),
        memoryBudgetMonitor: any MemoryBudgetMonitoring = LoaderMemoryBudgetMonitor(),
        modelCostEstimator: any ModelCostEstimating = FileSystemModelCostEstimator(),
        admissionEvaluator: LoadAdmissionEvaluator = LoadAdmissionEvaluator(),
        startHTTPServers: Bool = true
    ) {
        self.backendLoader = backendLoader
        self.piMonoLauncher = piMonoLauncher
        self.supervisor = supervisor
        self.memoryBudgetMonitor = memoryBudgetMonitor
        self.modelCostEstimator = modelCostEstimator
        self.admissionEvaluator = admissionEvaluator
        self.backendLoader.runtimeEventHandler = { [weak self] event in
            self?.handleBackendRuntimeEvent(event)
        }
        refreshModelDiscovery()
        refreshMemoryBudgetState()
        if startHTTPServers {
            startHTTPServer()
        }
    }

    var status: RuntimeStatus {
        supervisor.runtimeState
    }

    var supervisorSummary: String {
        supervisor.summaryText
    }

    var selectedModel: ModelRecord? {
        guard let selectedModelID else { return availableModels.first }
        return availableModels.first(where: { $0.id == selectedModelID }) ?? availableModels.first
    }

    var budgetReportSummary: String {
        let lifecycle = status.contractValue
        let selected = selectedModel?.id ?? "none"
        let footprint = lastMemoryBudgetSnapshot.map { ByteCountFormatter.loaderString(for: $0.combinedFootprintBytes) } ?? "unknown"
        let source = lastMemoryBudgetSnapshot?.measurementSource ?? "unknown"
        let admission = lastAdmissionDecision?.result ?? "not_run"
        let postLoad = lastPostLoadVerification?.result ?? "not_run"
        let reclaim = lastReclaimVerification?.result ?? "not_run"
        let recoveryAction = projectedRecoveryAction ?? "none"
        return """
        Lifecycle: \(lifecycle)
        Selected Model: \(selected)
        Measurement Source: \(source)
        Current Footprint: \(footprint)
        Admission: \(admission)
        Post-Load Verification: \(postLoad)
        Reclaim Verification: \(reclaim)
        Recovery Action: \(recoveryAction)
        """
    }

    func refreshModelDiscovery() {
        let rootURL = URL(fileURLWithPath: Self.modelRoot, isDirectory: true)
        let discovered = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?
            .compactMap { url -> ModelRecord? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else { return nil }
                return ModelRecord(
                    id: url.lastPathComponent,
                    displayName: url.lastPathComponent,
                    localPath: url.path
                )
            }
            .sorted(by: { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }) ?? []

        availableModels = discovered
        if selectedModel == nil {
            selectedModelID = discovered.first?.id
        }

        if let selectedModel {
            if !supervisor.isFailedFastActive {
                supervisor.transition(to: .idle)
            }
            statusDetail = "PEM-002 discovery complete. One real local MLX model can now be selected."
            discoverySummary = "\(discovered.count) models discovered under \(Self.modelRoot).\nSelected: \(selectedModel.displayName)"
        } else {
            if !supervisor.isFailedFastActive {
                supervisor.transition(to: .idle)
            }
            statusDetail = "PEM-002 discovery found no selectable model directories."
            discoverySummary = "0 models discovered under \(Self.modelRoot)."
        }
        refreshMemoryBudgetState()
    }

    func startHTTPServer() {
        let controlServer = LocalHTTPServer(delegate: self)
        let compatServer = LocalHTTPServer(delegate: self)
        do {
            try controlServer.start(onPort: Self.controlPort)
            try compatServer.start(onPort: Self.openAICompatPort)
            controlHTTPServer = controlServer
            openAICompatHTTPServer = compatServer
            updateServerSummary()
        } catch {
            serverSummary = "HTTP server failed to start: \(error.localizedDescription)"
        }
    }

    func piMonoButtonPressed() {
        do {
            try piMonoLauncher.launch()
            piMonoSummary = "pi-mono launched from \(piMonoLauncher.piMonoRoot.path)"
            statusDetail = "pi-mono launch path triggered. Use the loader HTTP endpoint for connection."
        } catch {
            piMonoSummary = error.localizedDescription
            statusDetail = "pi-mono launch path returned a structured loader-side message."
        }
    }

    func loadButtonPressed() {
        guard let selectedModel else {
            supervisor.transition(to: .failed)
            statusDetail = "No model is currently selectable."
            activeModelSummary = "Load blocked because no discovered MLX model is selected."
            return
        }

        do {
            _ = try evaluateAdmission(for: selectedModel)
        } catch let failure as BackendFailureReport {
            if failure.code != "failed_fast_active" {
                supervisor.transition(to: .failed)
            }
            statusDetail = "PEM-002 load admission denied before helper spawn."
            activeModelSummary = "Error: \(failure.code)\nDetail: \(failure.detail)"
            return
        } catch {
            supervisor.transition(to: .failed)
            statusDetail = "PEM-002 load admission failed unexpectedly."
            activeModelSummary = "Unexpected error: \(error.localizedDescription)"
            return
        }

        supervisor.transition(to: .loading)
        statusDetail = "Loading \(selectedModel.displayName) through the loader-owned MLX helper."
        activeModelSummary = "Starting selected-model load."
        reclaimSummary = "Reclaim verification not run yet."

        Task {
            do {
                let report = try await backendLoader.load(model: selectedModel)
                let verification = await verifyPostLoadBudget()
                if verification.result != "within_budget" {
                    supervisor.noteExpectedTermination(pid: backendLoader.activeHelperPID())
                    await backendLoader.shutdown()
                    supervisor.noteShutdownComplete()
                    supervisor.transition(to: .failed)
                    statusDetail = "PEM-003 post-load verification failed. Helper terminated after ready-state measurement."
                    activeModelSummary = "Error: \(verification.reasonCode ?? "post_load_budget_verification_failed")\nDetail: \(verification.detail)"
                    refreshMemoryBudgetState()
                    updateServerSummary()
                    return
                }

                supervisor.noteHelperReady(pid: backendLoader.activeHelperPID())
                statusDetail = "PEM-003 load complete. Selected model is resident and post-load verified."
                activeModelSummary = """
                Active model: \(report.modelID)
                Path: \(report.modelPath)
                Transport: \(report.transport)
                Note: \(report.note)
                """
                refreshMemoryBudgetState()
                updateServerSummary()
            } catch let failure as BackendFailureReport {
                supervisor.transition(to: .failed)
                statusDetail = "PEM-003 load failed with a structured loader error."
                activeModelSummary = "Error: \(failure.code)\nDetail: \(failure.detail)"
                refreshMemoryBudgetState()
            } catch {
                supervisor.transition(to: .failed)
                statusDetail = "PEM-003 load failed with an unexpected error."
                activeModelSummary = "Unexpected error: \(error.localizedDescription)"
                refreshMemoryBudgetState()
            }
        }
    }

    func resetButtonPressed() {
        if supervisor.isFailedFastActive {
            supervisor.clearFailedFastForOperatorRecovery()
            statusDetail = "PEM-007 operator reset cleared failed_fast before reclaim verification."
        }
        supervisor.transition(to: .loading)
        statusDetail = "Resetting loader state and unloading the active helper."
        resetSummary = "Reset in progress."

        Task {
            supervisor.noteExpectedTermination(pid: backendLoader.activeHelperPID())
            await backendLoader.shutdown()
            supervisor.noteShutdownComplete()
            let reclaimVerification = await verifyReclaimAfterReset()
            lastReclaimVerification = reclaimVerification
            reclaimSummary = reclaimVerification.summaryText
            if reclaimVerification.result == "reclaimed" {
                supervisor.transition(to: .idle)
                statusDetail = "PEM-004 reset complete. Reclaim verified and loader returned to reusable idle state."
                activeModelSummary = "No model loaded."
                generationSummary = "Prompt/response path is ready once one model is loaded."
                resetSummary = "Reset complete. Active backend cleared and reclaim verified."
                postLoadSummary = "Post-load verification not run yet."
            } else {
                supervisor.transition(to: .failed)
                statusDetail = "PEM-004 reset failed reclaim verification. Loader is not treated as healthy idle."
                activeModelSummary = "Error: \(reclaimVerification.reasonCode ?? "reclaim_verification_failed")\nDetail: \(reclaimVerification.detail)"
                generationSummary = "Prompt/response path blocked until reclaim issue is resolved."
                resetSummary = "Reset terminated the helper, but reclaim verification failed."
            }
            if let selectedModel {
                discoverySummary = "\(availableModels.count) models discovered under \(Self.modelRoot).\nSelected: \(selectedModel.displayName)"
            } else {
                discoverySummary = "\(availableModels.count) models discovered under \(Self.modelRoot)."
            }
            refreshMemoryBudgetState()
            updateServerSummary()
        }
    }

    func httpStatusPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "status": "ok",
            "runtime_state": status.contractValue,
            "selected_model_id": selectedModel?.id as Any,
            "selected_model_path": selectedModel?.localPath as Any,
            "server_summary": serverSummary,
            "memory_budget_status": memoryBudgetStatus,
            "budget_report": budgetReportPayload(),
            "supervisor_state": supervisor.statusPayload,
        ]
        if let projectedRecoveryAction {
            payload["recovery_action"] = projectedRecoveryAction
            payload["recovery_message"] = projectedRecoveryMessage
        }
        if let lastMemoryBudgetSnapshot {
            payload["memory_budget"] = lastMemoryBudgetSnapshot.asStatusPayload
        }
        if let lastAdmissionDecision {
            payload["last_admission"] = lastAdmissionDecision.asStatusPayload
        }
        if let lastPostLoadVerification {
            payload["last_post_load_verification"] = lastPostLoadVerification.asStatusPayload
        }
        if let lastReclaimVerification {
            payload["last_reclaim_verification"] = lastReclaimVerification.asStatusPayload
        }
        return payload
    }

    func httpModelsPayload() -> [[String: Any]] {
        availableModels.map { model in
            [
                "model_id": model.id,
                "display_name": model.displayName,
                "backend_kind": "mlx",
                "local_path": model.localPath,
            ]
        }
    }

    func httpLoadModel(modelID: String) async -> HTTPResponse {
        guard let model = availableModels.first(where: { $0.id == modelID }) else {
            return .json(statusCode: 404, ["status": "failed", "error": "model_not_found", "model_id": modelID])
        }
        selectedModelID = model.id
        loadButtonPressed()
        if let immediateFailure = compatibilityFailureResponseForCurrentState(defaultStatusCode: 503) {
            return immediateFailure
        }
        var payload: [String: Any] = [
            "status": status == .ready ? "ready" : status == .loading ? "loading" : "failed",
            "runtime_state": status.contractValue,
            "selected_model_id": selectedModel?.id as Any,
            "active_summary": activeModelSummary,
        ]
        if let lastAdmissionDecision {
            payload["last_admission"] = lastAdmissionDecision.asStatusPayload
        }
        if let lastPostLoadVerification {
            payload["last_post_load_verification"] = lastPostLoadVerification.asStatusPayload
        }
        return .json(payload)
    }

    func httpGenerate(prompt: String) async -> HTTPResponse {
        do {
            let response = try await backendLoader.generate(prompt: prompt)
            generationSummary = "Last prompt completed through the loader boundary."
            activeModelSummary += "\nLast prompt sent through HTTP generate."
            return .json([
                "status": "ok",
                "prompt": prompt,
                "response": response,
            ])
        } catch let failure as BackendFailureReport {
            generationSummary = "Generation failed: \(failure.code)"
            return .json(statusCode: 500, [
                "status": "failed",
                "error": failure.code,
                "detail": failure.detail,
            ])
        } catch {
            generationSummary = "Generation failed unexpectedly."
            return .json(statusCode: 500, [
                "status": "failed",
                "error": "unexpected_generate_error",
                "detail": error.localizedDescription,
            ])
        }
    }

    func httpReset() async -> HTTPResponse {
        resetButtonPressed()
        return .json([
            "status": "resetting",
            "runtime_state": status.contractValue,
            "selected_model_id": selectedModel?.id as Any,
            "reset_summary": resetSummary,
        ])
    }

    func httpOpenAIChatCompletions(bodyJSON: [String: Any]) async -> HTTPResponse {
        guard let rawModelID = bodyJSON["model"] as? String, !rawModelID.isEmpty else {
            return .json(statusCode: 400, [
                "error": [
                    "message": "model is required",
                    "type": "invalid_request_error",
                ],
            ])
        }

        let normalizedModelID = normalizeRequestedModelID(rawModelID)
        guard let model = availableModels.first(where: { $0.id == normalizedModelID }) else {
            return .json(statusCode: 404, [
                "error": [
                    "message": "model_not_found: \(rawModelID)",
                    "type": "invalid_request_error",
                ],
            ])
        }

        let chatMessages = buildChatMessagesFromOpenAIMessages(bodyJSON["messages"] as? [[String: Any]] ?? [])
        guard !chatMessages.isEmpty else {
            return .json(statusCode: 400, [
                "error": [
                    "message": "messages must contain at least one text prompt",
                    "type": "invalid_request_error",
                ],
            ])
        }

        if selectedModel?.id != model.id || status != .ready {
            selectedModelID = model.id
            do {
                _ = try evaluateAdmission(for: model)
                let report = try await backendLoader.load(model: model)
                let verification = await verifyPostLoadBudget()
                if verification.result != "within_budget" {
                    supervisor.noteExpectedTermination(pid: backendLoader.activeHelperPID())
                    await backendLoader.shutdown()
                    supervisor.noteShutdownComplete()
                    supervisor.transition(to: .failed)
                    statusDetail = "OpenAI-compatible bridge failed post-load verification and terminated the helper."
                    activeModelSummary = "Error: \(verification.reasonCode ?? "post_load_budget_verification_failed")\nDetail: \(verification.detail)"
                refreshMemoryBudgetState()
                return openAICompatibilityFailureResponse(
                    code: verification.reasonCode ?? "post_load_budget_verification_failed",
                    detail: verification.detail,
                    statusCode: 503
                )
            }
            supervisor.noteHelperReady(pid: backendLoader.activeHelperPID())
            statusDetail = "OpenAI-compatible bridge loaded \(report.modelID) for pi-mono."
                activeModelSummary = """
                Active model: \(report.modelID)
                Path: \(report.modelPath)
                Transport: \(report.transport)
                Note: \(report.note)
                """
                refreshMemoryBudgetState()
                updateServerSummary()
            } catch let failure as BackendFailureReport {
                if failure.code != "failed_fast_active" {
                    supervisor.transition(to: .failed)
                }
                statusDetail = "OpenAI-compatible bridge could not admit or load the requested model."
                activeModelSummary = "Error: \(failure.code)\nDetail: \(failure.detail)"
                refreshMemoryBudgetState()
                return openAICompatibilityFailureResponse(
                    code: failure.code,
                    detail: failure.detail,
                    statusCode: openAICompatibilityStatusCode(for: failure.code)
                )
            } catch {
                supervisor.transition(to: .failed)
                statusDetail = "OpenAI-compatible bridge hit an unexpected load error."
                activeModelSummary = "Unexpected error: \(error.localizedDescription)"
                return openAICompatibilityFailureResponse(
                    code: "internal_error",
                    detail: error.localizedDescription,
                    statusCode: 500
                )
            }
        }

        do {
            let responseText = try await backendLoader.generateChat(messages: chatMessages)
            generationSummary = "Last prompt completed through the OpenAI-compatible pi-mono bridge."
            let completionID = "chatcmpl-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let created = Int(Date().timeIntervalSince1970)
            if (bodyJSON["stream"] as? Bool) == true {
                let escaped = responseText
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                let chunk1 = "data: {\"id\":\"\(completionID)\",\"object\":\"chat.completion.chunk\",\"created\":\(created),\"model\":\"\(rawModelID)\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\(escaped)\"},\"finish_reason\":null}]}\n\n"
                let chunk2 = "data: {\"id\":\"\(completionID)\",\"object\":\"chat.completion.chunk\",\"created\":\(created),\"model\":\"\(rawModelID)\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
                let done = "data: [DONE]\n\n"
                return HTTPResponse(
                    statusCode: 200,
                    body: Data((chunk1 + chunk2 + done).utf8),
                    contentType: "text/event-stream"
                )
            }

            return .json([
                "id": completionID,
                "object": "chat.completion",
                "created": created,
                "model": rawModelID,
                "choices": [
                    [
                        "index": 0,
                        "message": [
                            "role": "assistant",
                            "content": responseText,
                        ],
                        "finish_reason": "stop",
                    ],
                ],
                "usage": [
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0,
                ],
            ])
        } catch let failure as BackendFailureReport {
            generationSummary = "pi-mono bridge generation failed: \(failure.code)"
            return openAICompatibilityFailureResponse(
                code: failure.code,
                detail: failure.detail,
                statusCode: openAICompatibilityStatusCode(for: failure.code)
            )
        } catch {
            generationSummary = "pi-mono bridge generation failed unexpectedly."
            return openAICompatibilityFailureResponse(
                code: "internal_error",
                detail: error.localizedDescription,
                statusCode: 500
            )
        }
    }

    private func normalizeRequestedModelID(_ rawModelID: String) -> String {
        if availableModels.contains(where: { $0.id == rawModelID }) {
            return rawModelID
        }
        if let suffix = rawModelID.split(separator: "/").last {
            return String(suffix)
        }
        return rawModelID
    }

    private func buildChatMessagesFromOpenAIMessages(_ messages: [[String: Any]]) -> [[String: String]] {
        messages.compactMap { message in
            guard let role = message["role"] as? String else { return nil }
            guard ["system", "developer", "user", "assistant"].contains(role) else { return nil }

            if let content = message["content"] as? String, !content.isEmpty {
                return ["role": role == "developer" ? "system" : role, "content": content]
            }

            if let contentParts = message["content"] as? [[String: Any]] {
                let textParts = contentParts.compactMap { part -> String? in
                    guard let type = part["type"] as? String, type == "text" else { return nil }
                    return part["text"] as? String
                }
                guard !textParts.isEmpty else { return nil }
                return ["role": role == "developer" ? "system" : role, "content": textParts.joined(separator: "\n")]
            }

            return nil
        }
    }

    private func updateServerSummary() {
        let control = controlHTTPServer?.port.map { "Control: http://127.0.0.1:\($0)" } ?? "Control: pending"
        let compat = openAICompatHTTPServer?.port.map { "OpenAI bridge: http://127.0.0.1:\($0)/v1" } ?? "OpenAI bridge: pending"
        serverSummary = "\(control)\n\(compat)"
    }

    private func budgetReportPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "lifecycle_state": status.contractValue,
            "selected_model_id": selectedModel?.id as Any,
            "selected_model_path": selectedModel?.localPath as Any,
            "measurement_status": memoryBudgetStatus,
            "supervisor_state": supervisor.statusPayload,
        ]
        if let projectedRecoveryAction {
            payload["recovery_action"] = projectedRecoveryAction
            payload["recovery_message"] = projectedRecoveryMessage
        }
        if let lastMemoryBudgetSnapshot {
            payload["memory_budget"] = lastMemoryBudgetSnapshot.asStatusPayload
        }
        if let lastAdmissionDecision {
            payload["last_admission"] = lastAdmissionDecision.asStatusPayload
        }
        if let lastPostLoadVerification {
            payload["last_post_load_verification"] = lastPostLoadVerification.asStatusPayload
        }
        if let lastReclaimVerification {
            payload["last_reclaim_verification"] = lastReclaimVerification.asStatusPayload
        }
        return payload
    }

    private func handleBackendRuntimeEvent(_ event: BackendRuntimeEvent) {
        supervisor.handleRuntimeEvent(event)
        switch event {
        case let .helperExitedUnexpectedly(pid, terminationStatus):
            statusDetail = "PEM-006 helper crash detected. Supervisor moved runtime into failed state."
            activeModelSummary = "Error: helper_crashed\nDetail: Unexpected helper exit pid=\(pid) status=\(terminationStatus)"
            generationSummary = projectedRecoveryMessage ?? "Prompt/response path unavailable until helper recovery."
            resetSummary = projectedRecoveryMessage ?? resetSummary
            piMonoSummary = "pi-mono bridge will receive the canonical recovery mapping on the next request."
            refreshMemoryBudgetState()
            updateServerSummary()
        }
    }

    private var projectedRecoveryAction: String? {
        switch status {
        case .failedFast:
            return "operator_reset_required"
        case .failed:
            return "operator_reset_recommended"
        default:
            return nil
        }
    }

    private var projectedRecoveryMessage: String? {
        switch status {
        case .failedFast:
            return "Service is fail-closed in failed_fast. Operator reset is required before new load admission."
        case .failed:
            return "Service is degraded. Operator reset is recommended before retrying the runtime lane."
        default:
            return nil
        }
    }

    private func openAICompatibilityStatusCode(for code: String) -> Int {
        switch code {
        case "failed_fast_active", "memory_measurement_unavailable", "memory_ceiling_exceeded",
             "post_load_budget_verification_failed", "reclaim_verification_failed", "model_not_loaded":
            return 503
        default:
            return 500
        }
    }

    private func openAICompatibilityFailureResponse(code: String, detail: String, statusCode: Int) -> HTTPResponse {
        var errorPayload: [String: Any] = [
            "message": detail,
            "type": code,
            "code": code,
            "loader_state": status.contractValue,
        ]
        if let projectedRecoveryAction {
            errorPayload["recovery_action"] = projectedRecoveryAction
            errorPayload["recovery_message"] = projectedRecoveryMessage
        }
        return .json(statusCode: statusCode, ["error": errorPayload])
    }

    private func compatibilityFailureResponseForCurrentState(defaultStatusCode: Int) -> HTTPResponse? {
        if let lastAdmissionDecision, lastAdmissionDecision.result == "denied" {
            return .json(statusCode: defaultStatusCode, [
                "status": "failed",
                "runtime_state": status.contractValue,
                "selected_model_id": selectedModel?.id as Any,
                "active_summary": activeModelSummary,
                "error": lastAdmissionDecision.reasonCode ?? "load_denied",
                "detail": lastAdmissionDecision.detail,
                "recovery_action": projectedRecoveryAction as Any,
                "recovery_message": projectedRecoveryMessage as Any,
                "last_admission": lastAdmissionDecision.asStatusPayload,
            ])
        }

        if status == .failedFast {
            return .json(statusCode: defaultStatusCode, [
                "status": "failed",
                "runtime_state": status.contractValue,
                "selected_model_id": selectedModel?.id as Any,
                "active_summary": activeModelSummary,
                "error": "failed_fast_active",
                "detail": projectedRecoveryMessage ?? "Load admission is blocked while failed_fast is active.",
                "recovery_action": projectedRecoveryAction as Any,
                "recovery_message": projectedRecoveryMessage as Any,
            ])
        }

        return nil
    }

    private func evaluateAdmission(for model: ModelRecord) throws -> AdmissionDecision {
        if supervisor.isFailedFastActive {
            let denied = AdmissionDecision(
                result: "denied",
                reasonCode: "failed_fast_active",
                detail: "Load admission is blocked while failed_fast is active.",
                measurementSource: lastMemoryBudgetSnapshot?.measurementSource ?? "resident_size",
                currentFootprintBytes: lastMemoryBudgetSnapshot?.combinedFootprintBytes ?? 0,
                projectedModelCostBytes: 0,
                generationHeadroomBytes: MemoryBudgetConstants.baseline.generationHeadroomBytes,
                hostReserveBytes: MemoryBudgetConstants.baseline.hostReserveBytes,
                effectiveCeilingBytes: MemoryBudgetConstants.baseline.loaderMemoryCeilingBytes,
                projectedTotalBytes: 0
            )
            lastAdmissionDecision = denied
            admissionSummary = denied.summaryText
            throw BackendFailureReport(code: "failed_fast_active", detail: denied.detail)
        }
        let snapshot: MemoryBudgetSnapshot
        do {
            snapshot = try memoryBudgetMonitor.snapshot(helperPID: backendLoader.activeHelperPID())
        } catch {
            lastMemoryBudgetSnapshot = nil
            memoryBudgetStatus = "Measurement failed."
            memoryBudgetSummary = "Source: resident_size\nError: \(error.localizedDescription)"
            let denied = AdmissionDecision(
                result: "denied",
                reasonCode: "memory_measurement_unavailable",
                detail: error.localizedDescription,
                measurementSource: "resident_size",
                currentFootprintBytes: 0,
                projectedModelCostBytes: 0,
                generationHeadroomBytes: MemoryBudgetConstants.baseline.generationHeadroomBytes,
                hostReserveBytes: MemoryBudgetConstants.baseline.hostReserveBytes,
                effectiveCeilingBytes: 0,
                projectedTotalBytes: 0
            )
            lastAdmissionDecision = denied
            admissionSummary = denied.summaryText
            throw BackendFailureReport(code: "memory_measurement_unavailable", detail: error.localizedDescription)
        }

        lastMemoryBudgetSnapshot = snapshot
        memoryBudgetStatus = "Measurement ready."
        memoryBudgetSummary = snapshot.summaryText

        let projectedModelCostBytes = try modelCostEstimator.estimatedModelBytes(at: model.localPath)
        let decision = admissionEvaluator.evaluate(snapshot: snapshot, projectedModelCostBytes: projectedModelCostBytes)
        lastAdmissionDecision = decision
        admissionSummary = decision.summaryText
        if backendLoader.activeHelperPID() == nil {
            reusableIdleBaselineBytes = snapshot.combinedFootprintBytes
        }
        if decision.result == "allowed" {
            return decision
        }
        throw BackendFailureReport(code: decision.reasonCode ?? "memory_ceiling_exceeded", detail: decision.detail)
    }

    private func verifyPostLoadBudget() async -> PostLoadVerificationDecision {
        let snapshot: MemoryBudgetSnapshot
        do {
            snapshot = try memoryBudgetMonitor.snapshot(helperPID: backendLoader.activeHelperPID())
        } catch {
            refreshMemoryBudgetState()
            let verification = PostLoadVerificationDecision(
                result: "measurement_failed",
                reasonCode: "post_load_budget_verification_failed",
                detail: error.localizedDescription,
                measurementSource: "resident_size",
                measuredFootprintBytes: 0,
                effectiveCeilingBytes: 0
            )
            lastPostLoadVerification = verification
            postLoadSummary = verification.summaryText
            return verification
        }

        lastMemoryBudgetSnapshot = snapshot
        memoryBudgetStatus = "Measurement ready."
        memoryBudgetSummary = snapshot.summaryText

        let verification = admissionEvaluator.evaluatePostLoad(snapshot: snapshot)
        lastPostLoadVerification = verification
        postLoadSummary = verification.summaryText
        return verification
    }

    private func verifyReclaimAfterReset() async -> ReclaimVerificationDecision {
        let baselineFootprintBytes = reusableIdleBaselineBytes ?? 0
        let snapshot: MemoryBudgetSnapshot
        do {
            snapshot = try memoryBudgetMonitor.snapshot(helperPID: backendLoader.activeHelperPID())
        } catch {
            refreshMemoryBudgetState()
            return ReclaimVerificationDecision(
                result: "measurement_failed",
                reasonCode: "reclaim_verification_failed",
                detail: error.localizedDescription,
                measurementSource: "resident_size",
                baselineFootprintBytes: baselineFootprintBytes,
                measuredFootprintBytes: 0,
                reclaimSlackBytes: MemoryBudgetConstants.baseline.reclaimSlackBytes
            )
        }

        lastMemoryBudgetSnapshot = snapshot
        memoryBudgetStatus = "Measurement ready."
        memoryBudgetSummary = snapshot.summaryText
        let decision = admissionEvaluator.evaluateReclaim(
            baselineFootprintBytes: baselineFootprintBytes,
            snapshot: snapshot
        )
        if decision.result == "reclaimed" {
            reusableIdleBaselineBytes = snapshot.combinedFootprintBytes
        }
        return decision
    }

    private func refreshMemoryBudgetState() {
        do {
            let snapshot = try memoryBudgetMonitor.snapshot(helperPID: backendLoader.activeHelperPID())
            lastMemoryBudgetSnapshot = snapshot
            memoryBudgetStatus = "Measurement ready."
            memoryBudgetSummary = snapshot.summaryText
            if snapshot.helperPID == nil {
                reusableIdleBaselineBytes = snapshot.combinedFootprintBytes
            }
        } catch {
            lastMemoryBudgetSnapshot = nil
            memoryBudgetStatus = "Measurement failed."
            memoryBudgetSummary = "Source: resident_size\nError: \(error.localizedDescription)"
        }
    }

}
