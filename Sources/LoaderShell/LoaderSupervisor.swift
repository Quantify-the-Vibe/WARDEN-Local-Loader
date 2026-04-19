import Foundation

enum LoaderRuntimeState: String, Sendable {
    case idle = "Idle"
    case bootstrapping = "Bootstrapping"
    case loading = "Loading"
    case ready = "Ready"
    case failed = "Failed"
    case failedFast = "Failed Fast"

    var contractValue: String {
        switch self {
        case .idle:
            "idle"
        case .bootstrapping:
            "bootstrapping"
        case .loading:
            "loading"
        case .ready:
            "ready"
        case .failed:
            "failed"
        case .failedFast:
            "failed_fast"
        }
    }
}

@MainActor
@Observable
final class LoaderSupervisor {
    enum ConfigurationError: Error {
        case invalidCrashWindowInvariant(
            crashWindowSeconds: TimeInterval,
            maxCrashEquivalentTimeoutSeconds: TimeInterval,
            requiredMinimumSeconds: TimeInterval
        )
    }

    private let crashLimit: Int
    private let crashWindow: TimeInterval
    private let maxCrashEquivalentTimeoutSeconds: TimeInterval
    private let now: () -> Date

    private(set) var runtimeState: LoaderRuntimeState = .bootstrapping
    private(set) var crashCount = 0
    private(set) var lastCrashSummary = "No helper crash observed."
    private(set) var activeHelperPID: Int32?
    private(set) var crashTimestamps: [Date] = []
    private var expectedTerminationPID: Int32?

    init(
        crashLimit: Int = 3,
        crashWindow: TimeInterval = 900,
        maxCrashEquivalentTimeoutSeconds: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) throws {
        let requiredMinimumWindow = maxCrashEquivalentTimeoutSeconds * 3
        if crashWindow < requiredMinimumWindow {
            throw ConfigurationError.invalidCrashWindowInvariant(
                crashWindowSeconds: crashWindow,
                maxCrashEquivalentTimeoutSeconds: maxCrashEquivalentTimeoutSeconds,
                requiredMinimumSeconds: requiredMinimumWindow
            )
        }
        self.crashLimit = crashLimit
        self.crashWindow = crashWindow
        self.maxCrashEquivalentTimeoutSeconds = maxCrashEquivalentTimeoutSeconds
        self.now = now
    }

    func transition(to state: LoaderRuntimeState) {
        runtimeState = state
        if state == .idle {
            activeHelperPID = nil
        }
    }

    func noteHelperReady(pid: Int32?) {
        activeHelperPID = pid
        runtimeState = .ready
    }

    func noteExpectedTermination(pid: Int32?) {
        expectedTerminationPID = pid
    }

    func noteShutdownComplete() {
        activeHelperPID = nil
        expectedTerminationPID = nil
    }

    func clearFailedFastForOperatorRecovery() {
        guard runtimeState == .failedFast else { return }
        runtimeState = .idle
        crashTimestamps.removeAll()
        lastCrashSummary = "Operator cleared failed_fast and supervisor returned to idle."
    }

    func handleRuntimeEvent(_ event: BackendRuntimeEvent) {
        switch event {
        case let .helperExitedUnexpectedly(pid, terminationStatus):
            if expectedTerminationPID == pid {
                expectedTerminationPID = nil
                activeHelperPID = nil
                return
            }
            activeHelperPID = nil
            recordCrashEquivalentEvent(
                summary: "Unexpected helper exit. pid=\(pid) status=\(terminationStatus)",
                errorCode: "helper_exited_unexpectedly"
            )
        case let .helperReadyTimeout(timeoutSeconds):
            activeHelperPID = nil
            recordCrashEquivalentEvent(
                summary: "Helper ready timeout. timeout_seconds=\(Int(timeoutSeconds))",
                errorCode: "helper_ready_timeout"
            )
        case let .helperGenerateTimeout(timeoutSeconds):
            recordCrashEquivalentEvent(
                summary: "Helper generate timeout. timeout_seconds=\(Int(timeoutSeconds))",
                errorCode: "helper_generate_timeout"
            )
        }
    }

    private func recordCrashEquivalentEvent(summary: String, errorCode: String) {
        crashCount += 1
        let eventTime = now()
        crashTimestamps.append(eventTime)
        let windowStart = eventTime.addingTimeInterval(-crashWindow)
        crashTimestamps.removeAll { $0 < windowStart }
        if crashTimestamps.count > crashLimit {
            runtimeState = .failedFast
            lastCrashSummary = "\(summary) count=\(crashCount) window_count=\(crashTimestamps.count) code=\(errorCode) entered=failed_fast"
        } else {
            runtimeState = .failed
            lastCrashSummary = "\(summary) count=\(crashCount) window_count=\(crashTimestamps.count) code=\(errorCode)"
        }
    }

    var isFailedFastActive: Bool {
        runtimeState == .failedFast
    }

    var summaryText: String {
        """
        Lifecycle: \(runtimeState.contractValue)
        Active Helper PID: \(activeHelperPID.map(String.init) ?? "none")
        Crash Count: \(crashCount)
        Crash Window Count: \(crashTimestamps.count)
        Last Crash: \(lastCrashSummary)
        """
    }

    var statusPayload: [String: Any] {
        [
            "runtime_state": runtimeState.contractValue,
            "active_helper_pid": activeHelperPID.map(Int.init) as Any,
            "crash_count": crashCount,
            "crash_window_count": crashTimestamps.count,
            "crash_limit": crashLimit,
            "crash_window_seconds": Int(crashWindow),
            "max_crash_equivalent_timeout_seconds": Int(maxCrashEquivalentTimeoutSeconds),
            "failed_fast_active": isFailedFastActive,
            "last_crash_summary": lastCrashSummary,
        ]
    }
}
