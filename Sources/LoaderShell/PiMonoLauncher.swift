import Foundation

enum PiMonoLauncherError: LocalizedError {
    case missingRepo(String)
    case missingLauncherScript(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRepo(let message), .missingLauncherScript(let message), .launchFailed(let message):
            return message
        }
    }
}

struct PiMonoLauncher: Sendable {
    let piMonoRoot: URL

    static func `default`() -> PiMonoLauncher {
        let processInfo = ProcessInfo.processInfo
        let root = processInfo.environment["LOCAL_LLM_LOADER_PI_MONO_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appending(path: "pi-mono")
        return PiMonoLauncher(piMonoRoot: root)
    }

    func launch() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: piMonoRoot.path) else {
            throw PiMonoLauncherError.missingRepo(
                "pi-mono repo not found at \(piMonoRoot.path). Set LOCAL_LLM_LOADER_PI_MONO_ROOT if it lives elsewhere."
            )
        }

        let launcherScript = piMonoRoot.appending(path: "pi-test.sh")
        guard fileManager.isExecutableFile(atPath: launcherScript.path) else {
            throw PiMonoLauncherError.missingLauncherScript(
                "pi-mono launcher script not executable at \(launcherScript.path)."
            )
        }

        let escapedRoot = shellQuoted(piMonoRoot.path)
        let command = "cd \(escapedRoot) && ./pi-test.sh"
        let appleScript = """
        tell application "Terminal"
            activate
            do script \(appleScriptQuoted(command))
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? "<non-utf8>"
            throw PiMonoLauncherError.launchFailed("Failed to launch pi-mono in Terminal: \(stderrText)")
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
