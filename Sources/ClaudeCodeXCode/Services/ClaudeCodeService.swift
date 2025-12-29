import Foundation

/// Service for Claude Code utilities
/// Note: Process management moved to SwiftTerm's LocalProcessTerminalView
@MainActor
class ClaudeCodeService: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var workingDirectory: URL?

    init() {
        // Try to get current Xcode project root, fallback to home directory
        if let projectRoot = XcodeIntegration.getCurrentProjectRoot() {
            workingDirectory = projectRoot
        } else {
            workingDirectory = FileManager.default.homeDirectoryForCurrentUser
        }
    }

    /// Find the claude executable path
    /// Made static so it can be used by TerminalView
    static func findClaudePath() -> String {
        // Check common locations
        let possiblePaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "\(NSHomeDirectory())/node_modules/.bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try using `which` to find it
        let whichProcess = Process()
        let pipe = Pipe()

        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["claude"]
        whichProcess.standardOutput = pipe

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {
            // Fall through to default
        }

        // Default fallback
        return "/usr/local/bin/claude"
    }

    /// Check if Claude Code CLI is installed
    static func isClaudeInstalled() -> Bool {
        let path = findClaudePath()
        return FileManager.default.fileExists(atPath: path)
    }

    /// Get Claude Code version if available
    static func getClaudeVersion() -> String? {
        let path = findClaudePath()
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !version.isEmpty {
                return version
            }
        } catch {
            return nil
        }

        return nil
    }

    /// Set working directory for Claude
    func setWorkingDirectory(_ url: URL) {
        workingDirectory = url
    }

    /// Process terminated handler
    func handleProcessTerminated(exitCode: Int32?) {
        isRunning = false
        if let code = exitCode, code != 0 {
            print("Claude Code exited with code: \(code)")
        }
    }

    /// Process started handler
    func handleProcessStarted() {
        isRunning = true
    }
}
