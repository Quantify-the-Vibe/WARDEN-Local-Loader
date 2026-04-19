import Foundation

@MainActor
final class MLXBackendLoader: BackendLoader {
    var runtimeEventHandler: ((BackendRuntimeEvent) -> Void)?

    private var activeProcess: Process?
    private var activeInputPipe: Pipe?
    private var activeOutputPipe: Pipe?
    private var expectedTerminationPID: Int32?

    func load(model: LoaderShellViewModel.ModelRecord) async throws -> BackendReadyReport {
        await shutdown()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "/Users/kikbot/Documents/WARDEN4/WARDEN4-Local-LLM-Loader-Rebuild/tools/mlx_loader_helper.py",
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

        let output = try await withCheckedThrowingContinuation { continuation in
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

        let output = try await withCheckedThrowingContinuation { continuation in
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

        let response = try Self.decodePayload(output)
        guard response["status"] as? String == "ok" else {
            throw BackendFailureReport(
                code: response["error"] as? String ?? "generate_failed",
                detail: response["detail"] as? String ?? "MLX helper returned a structured generation failure."
            )
        }
        return response["response"] as? String ?? ""
    }

    func generateChat(messages: [[String: String]]) async throws -> String {
        guard let activeProcess, activeProcess.isRunning,
              let activeInputPipe,
              let activeOutputPipe
        else {
            throw BackendFailureReport(code: "model_not_loaded", detail: "Generate requires one active loaded model.")
        }

        let payload = try JSONSerialization.data(withJSONObject: ["command": "generate_chat", "messages": messages])
        try activeInputPipe.fileHandleForWriting.write(contentsOf: payload)
        try activeInputPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))

        let output = try await withCheckedThrowingContinuation { continuation in
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

        let response = try Self.decodePayload(output)
        guard response["status"] as? String == "ok" else {
            throw BackendFailureReport(
                code: response["error"] as? String ?? "generate_chat_failed",
                detail: response["detail"] as? String ?? "MLX helper returned a structured chat generation failure."
            )
        }
        return response["response"] as? String ?? ""
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
            throw BackendFailureReport(code: "helper_timeout", detail: "MLX helper did not report readiness before timeout.")
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
}
