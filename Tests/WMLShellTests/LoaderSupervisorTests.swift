import Foundation
import Testing
@testable import WMLShell

struct LoaderSupervisorTests {
    @MainActor
    @Test
    func invalidCrashWindowInvariantIsRejected() {
        do {
            _ = try LoaderSupervisor(
                crashLimit: 3,
                crashWindow: 60,
                maxCrashEquivalentTimeoutSeconds: 300,
                now: Date.init
            )
            Issue.record("Expected invalid crash-window configuration to be rejected.")
        } catch LoaderSupervisor.ConfigurationError.invalidCrashWindowInvariant(
            let crashWindowSeconds,
            let timeoutSeconds,
            let requiredMinimumSeconds
        ) {
            #expect(Int(crashWindowSeconds) == 60)
            #expect(Int(timeoutSeconds) == 300)
            #expect(Int(requiredMinimumSeconds) == 900)
        } catch {
            Issue.record("Unexpected configuration error: \(error)")
        }
    }

    @MainActor
    @Test
    func timeoutEventsAreCrashEquivalentAndVisibleInStatus() async throws {
        var tick: TimeInterval = 0
        let supervisor = try LoaderSupervisor(
            crashLimit: 5,
            crashWindow: 900,
            maxCrashEquivalentTimeoutSeconds: 300,
            now: {
                defer { tick += 1 }
                return Date(timeIntervalSince1970: tick)
            }
        )

        supervisor.handleRuntimeEvent(.helperReadyTimeout(timeoutSeconds: 120))
        #expect(supervisor.runtimeState == .failed)
        #expect(supervisor.crashCount == 1)
        #expect(supervisor.statusPayload["crash_window_count"] as? Int == 1)
        let firstSummary = supervisor.statusPayload["last_crash_summary"] as? String
        #expect(firstSummary?.contains("code=helper_ready_timeout") == true)

        supervisor.handleRuntimeEvent(.helperGenerateTimeout(timeoutSeconds: 300))
        #expect(supervisor.runtimeState == .failed)
        #expect(supervisor.crashCount == 2)
        #expect(supervisor.statusPayload["crash_window_count"] as? Int == 2)
        let secondSummary = supervisor.statusPayload["last_crash_summary"] as? String
        #expect(secondSummary?.contains("code=helper_generate_timeout") == true)
    }

    @MainActor
    @Test
    func repeatedTimeoutEventsCanEnterFailedFast() async throws {
        var tick: TimeInterval = 0
        let supervisor = try LoaderSupervisor(
            crashLimit: 1,
            crashWindow: 900,
            maxCrashEquivalentTimeoutSeconds: 300,
            now: {
                defer { tick += 1 }
                return Date(timeIntervalSince1970: tick)
            }
        )

        supervisor.handleRuntimeEvent(.helperGenerateTimeout(timeoutSeconds: 300))
        #expect(supervisor.runtimeState == .failed)
        supervisor.handleRuntimeEvent(.helperGenerateTimeout(timeoutSeconds: 300))
        #expect(supervisor.runtimeState == .failedFast)
        #expect(supervisor.isFailedFastActive == true)
        #expect(supervisor.nextRestartBackoffSeconds == nil)
    }

    @MainActor
    @Test
    func restartBackoffFollowsBoundedSequence() async throws {
        var tick: TimeInterval = 0
        let supervisor = try LoaderSupervisor(
            crashLimit: 5,
            crashWindow: 900,
            maxCrashEquivalentTimeoutSeconds: 300,
            restartBackoffScheduleSeconds: [2, 4, 8],
            now: {
                defer { tick += 1 }
                return Date(timeIntervalSince1970: tick)
            }
        )

        supervisor.handleRuntimeEvent(.helperReadyTimeout(timeoutSeconds: 120))
        #expect(supervisor.nextRestartBackoffSeconds == 2)

        supervisor.handleRuntimeEvent(.helperGenerateTimeout(timeoutSeconds: 300))
        #expect(supervisor.nextRestartBackoffSeconds == 4)

        supervisor.handleRuntimeEvent(.helperExitedUnexpectedly(pid: 44, terminationStatus: 9))
        #expect(supervisor.nextRestartBackoffSeconds == 8)

        supervisor.handleRuntimeEvent(.helperGenerateTimeout(timeoutSeconds: 300))
        #expect(supervisor.nextRestartBackoffSeconds == 8)
    }
}
