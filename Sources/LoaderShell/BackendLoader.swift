import Foundation

enum BackendRuntimeEvent: Sendable {
    case helperExitedUnexpectedly(pid: Int32, terminationStatus: Int32)
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

@MainActor
protocol BackendLoader: AnyObject {
    var runtimeEventHandler: ((BackendRuntimeEvent) -> Void)? { get set }
    func load(model: LoaderShellViewModel.ModelRecord) async throws -> BackendReadyReport
    func generate(prompt: String) async throws -> String
    func generateChat(messages: [[String: String]]) async throws -> String
    func shutdown() async
    func activeHelperPID() -> Int32?
}
