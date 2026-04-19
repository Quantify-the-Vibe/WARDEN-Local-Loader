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
    private let crashLimit: Int
    private let crashWindow: TimeInterval
    private let now: () -> Date

    private(set) var runtimeState: LoaderRuntimeState = .bootstrapping
    private(set) var crashCount = 0
    private(set) var lastCrashSummary = "No helper crash observed."
    private(set) var activeHelperPID: Int32?
    private(set) var crashTimestamps: [Date] = []
    private var expectedTerminationPID: Int32?

    init(
        crashLimit: Int = 3,
        crashWindow: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.crashLimit = crashLimit
        self.crashWindow = crashWindow
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
            crashCount += 1
            let eventTime = now()
            crashTimestamps.append(eventTime)
            let windowStart = eventTime.addingTimeInterval(-crashWindow)
            crashTimestamps.removeAll { $0 < windowStart }
            activeHelperPID = nil
            if crashTimestamps.count > crashLimit {
                runtimeState = .failedFast
                lastCrashSummary = "Unexpected helper exit. pid=\(pid) status=\(terminationStatus) count=\(crashCount) window_count=\(crashTimestamps.count) entered=failed_fast"
            } else {
                runtimeState = .failed
                lastCrashSummary = "Unexpected helper exit. pid=\(pid) status=\(terminationStatus) count=\(crashCount) window_count=\(crashTimestamps.count)"
            }
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
            "failed_fast_active": isFailedFastActive,
            "last_crash_summary": lastCrashSummary,
        ]
    }
}
