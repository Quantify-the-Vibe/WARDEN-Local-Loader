import Foundation

@MainActor
final class MLXBackendLoader: BackendLoader {
    var runtimeEventHandler: ((BackendRuntimeEvent) -> Void)?

    private var activeProcess: Process?
    private var activeInputPipe: Pipe?
    private var activeOutputPipe: Pipe?
    private var expectedTerminationPID: Int32?

    func load(model: WMLShellViewModel.ModelRecord) async throws -> BackendReadyReport {
        await shutdown()
        let helperScriptPath = try Self.resolveHelperScriptPath()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            helperScriptPath,
            "--model-id", model.id,
            "--model-path", model.localPath,
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                guard let self else { return }
                let pid = terminatedProcess.processIdentifier
                let terminationStatus = terminatedProcess.terminationStatus
                let expected = self.expectedTerminationPID == pid
                if self.activeProcess?.processIdentifier == pid {
                    self.activeProcess = nil
                    self.activeInputPipe = nil
                    self.activeOutputPipe = nil
                }
                if expected {
                    self.expectedTerminationPID = nil
                    return
                }
                self.runtimeEventHandler?(
                    .helperExitedUnexpectedly(pid: pid, terminationStatus: terminationStatus)
                )
            }
        }

        try process.run()

        let output: String
        do {
            output = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(
                            returning: try Self.readOneLine(from: stdoutPipe.fileHandleForReading, timeout: 120)
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch let failure as BackendFailureReport where failure.code == "helper_timeout" {
            runtimeEventHandler?(.helperReadyTimeout(timeoutSeconds: 120))
            throw BackendFailureReport(
                code: "helper_ready_timeout",
                detail: "MLX helper did not report readiness before timeout."
            )
        }

        let payload = try Self.decodePayload(output)
        if payload["status"] as? String == "ready" {
            activeProcess = process
            activeInputPipe = stdinPipe
            activeOutputPipe = stdoutPipe
            return BackendReadyReport(
                modelID: payload["model_id"] as? String ?? model.id,
                modelPath: payload["model_path"] as? String ?? model.localPath,
                pidText: payload["pid"].map { String(describing: $0) },
                transport: payload["transport"] as? String ?? "swift->python->mlx",
                note: payload["note"] as? String ?? "Model loaded."
            )
        }

        let stderrText = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let detail = payload["detail"] as? String ?? stderrText
        throw BackendFailureReport(
            code: payload["error"] as? String ?? "mlx_load_failed",
            detail: detail.isEmpty ? "MLX helper returned a structured failure." : detail
        )
    }

    func generate(prompt: String) async throws -> String {
        guard let activeProcess, activeProcess.isRunning,
              let activeInputPipe,
              let activeOutputPipe
        else {
            throw BackendFailureReport(code: "model_not_loaded", detail: "Generate requires one active loaded model.")
        }

        let payload = try JSONSerialization.data(withJSONObject: ["command": "generate", "prompt": prompt])
        try activeInputPipe.fileHandleForWriting.write(contentsOf: payload)
        try activeInputPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))

        let output: String
        do {
            output = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(
                            returning: try Self.readOneLine(from: activeOutputPipe.fileHandleForReading, timeout: 300)
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch let failure as BackendFailureReport where failure.code == "helper_timeout" {
            runtimeEventHandler?(.helperGenerateTimeout(timeoutSeconds: 300))
            throw BackendFailureReport(
                code: "helper_generate_timeout",
                detail: "MLX helper did not return generation output before timeout."
            )
        }

        let response = try Self.decodePayload(output)
        guard response["status"] as? String == "ok" else {
            throw BackendFailureReport(
                code: response["error"] as? String ?? "generate_failed",
                detail: response["detail"] as? String ?? "MLX helper returned a structured generation failure."
            )
        }
        return response["response"] as? String ?? ""
    }

    func generateChat(messages: [[String: String]], maxTokens: Int?) async throws -> BackendChatGenerateResult {
        guard let activeProcess, activeProcess.isRunning,
              let activeInputPipe,
              let activeOutputPipe
        else {
            throw BackendFailureReport(code: "model_not_loaded", detail: "Generate requires one active loaded model.")
        }

        var command: [String: Any] = ["command": "generate_chat", "messages": messages]
        if let maxTokens, maxTokens > 0 {
            command["max_tokens"] = maxTokens
        }
        let payload = try JSONSerialization.data(withJSONObject: command)
        try activeInputPipe.fileHandleForWriting.write(contentsOf: payload)
        try activeInputPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))

        let output: String
        do {
            output = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(
                            returning: try Self.readOneLine(from: activeOutputPipe.fileHandleForReading, timeout: 300)
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch let failure as BackendFailureReport where failure.code == "helper_timeout" {
            runtimeEventHandler?(.helperGenerateTimeout(timeoutSeconds: 300))
            throw BackendFailureReport(
                code: "helper_generate_timeout",
                detail: "MLX helper did not return chat generation output before timeout."
            )
        }

        let response = try Self.decodePayload(output)
        guard response["status"] as? String == "ok" else {
            throw BackendFailureReport(
                code: response["error"] as? String ?? "generate_chat_failed",
                detail: response["detail"] as? String ?? "MLX helper returned a structured chat generation failure."
            )
        }
        return BackendChatGenerateResult(
            text: response["response"] as? String ?? "",
            finishReason: response["finish_reason"] as? String ?? "stop",
            promptTokens: response["prompt_tokens"] as? Int,
            completionTokens: response["completion_tokens"] as? Int
        )
    }

    func shutdown() async {
        guard let activeProcess else { return }
        expectedTerminationPID = activeProcess.processIdentifier
        if let activeInputPipe {
            let payload = #"{"command":"shutdown"}"#
            if let data = (payload + "\n").data(using: .utf8) {
                try? activeInputPipe.fileHandleForWriting.write(contentsOf: data)
            }
        }
        activeProcess.terminate()
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                activeProcess.waitUntilExit()
                continuation.resume()
            }
        }
        if self.activeProcess?.processIdentifier == activeProcess.processIdentifier {
            self.activeProcess = nil
            self.activeInputPipe = nil
            self.activeOutputPipe = nil
        }
        if self.expectedTerminationPID == activeProcess.processIdentifier {
            self.expectedTerminationPID = nil
        }
    }

    func activeHelperPID() -> Int32? {
        guard let activeProcess, activeProcess.isRunning else {
            return nil
        }
        return activeProcess.processIdentifier
    }

    nonisolated private static func readOneLine(from handle: FileHandle, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        while Date() < deadline {
            let chunk = try handle.read(upToCount: 1) ?? Data()
            if chunk.isEmpty {
                usleep(10_000)
                continue
            }
            if chunk == Data([0x0A]) {
                break
            }
            data.append(chunk)
        }

        guard !data.isEmpty else {
            throw BackendFailureReport(code: "helper_timeout", detail: "MLX helper did not respond before timeout.")
        }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func decodePayload(_ line: String) throws -> [String: Any] {
        guard let data = line.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw BackendFailureReport(code: "invalid_helper_payload", detail: "Helper returned invalid JSON.")
        }
        return payload
    }

    nonisolated private static func resolveHelperScriptPath() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let fileManager = FileManager.default
        var candidates: [String] = []
        let helperRelativePath = "tools/mlx_loader_helper.py"

        if let envPath = environment["WML_HELPER_SCRIPT_PATH"], !envPath.isEmpty {
            candidates.append(envPath)
        }

        let cwd = fileManager.currentDirectoryPath
        candidates.append(URL(fileURLWithPath: cwd, isDirectory: true).appendingPathComponent(helperRelativePath).path)

        if let executableURL = Bundle.main.executableURL {
            var cursor = executableURL.deletingLastPathComponent()
            for _ in 0..<10 {
                candidates.append(cursor.appendingPathComponent(helperRelativePath).path)
                let parent = cursor.deletingLastPathComponent()
                if parent.path == cursor.path {
                    break
                }
                cursor = parent
            }
        }

        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("mlx_loader_helper.py").path {
            candidates.append(bundlePath)
        }

        guard let selected = candidates.first(where: { fileManager.fileExists(atPath: $0) }) else {
            throw BackendFailureReport(
                code: "helper_script_missing",
                detail: "MLX helper script not found. Set WML_HELPER_SCRIPT_PATH or ensure tools/mlx_loader_helper.py exists."
            )
        }

        if (try? fileManager.destinationOfSymbolicLink(atPath: selected)) != nil {
            throw BackendFailureReport(
                code: "helper_script_untrusted",
                detail: "MLX helper script path must not be a symbolic link."
            )
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: selected),
           let permissions = attributes[.posixPermissions] as? NSNumber,
           permissions.intValue & 0o002 != 0 {
            throw BackendFailureReport(
                code: "helper_script_untrusted",
                detail: "MLX helper script is world-writable. Refusing to execute untrusted helper."
            )
        }

        return selected
    }
}
