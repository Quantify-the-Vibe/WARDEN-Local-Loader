import Foundation

enum BackendRuntimeEvent: Sendable {
    case helperExitedUnexpectedly(pid: Int32, terminationStatus: Int32)
    case helperReadyTimeout(timeoutSeconds: TimeInterval)
    case helperGenerateTimeout(timeoutSeconds: TimeInterval)
}

struct BackendReadyReport {
    let modelID: String
    let modelPath: String
    let pidText: String?
    let transport: String
    let note: String
}

struct BackendFailureReport: Error {
    let code: String
    let detail: String
}

struct BackendChatGenerateResult {
    let text: String
    let finishReason: String
    let promptTokens: Int?
    let completionTokens: Int?
}

@MainActor
protocol BackendLoader: AnyObject {
    var runtimeEventHandler: ((BackendRuntimeEvent) -> Void)? { get set }
    func load(model: LoaderShellViewModel.ModelRecord) async throws -> BackendReadyReport
    func generate(prompt: String) async throws -> String
    func generateChat(messages: [[String: String]], maxTokens: Int?) async throws -> BackendChatGenerateResult
    func shutdown() async
    func activeHelperPID() -> Int32?
}
