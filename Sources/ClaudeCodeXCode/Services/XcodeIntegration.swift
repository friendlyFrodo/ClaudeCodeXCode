import Foundation
import AppKit

/// Service for integrating with Xcode via AppleScript and other APIs
class XcodeIntegration {

    /// Get the root directory of the currently open Xcode project/workspace
    /// Returns nil if Xcode isn't running or no project is open
    static func getCurrentProjectRoot() -> URL? {
        // Don't even try if Xcode isn't running
        guard isXcodeRunning() else {
            return nil
        }

        // Try to get the workspace/project path from Xcode
        if let workspacePath = getXcodeWorkspacePath() {
            // Workspace path is like /path/to/Project.xcworkspace
            // We want the parent directory
            let url = URL(fileURLWithPath: workspacePath)
            return url.deletingLastPathComponent()
        }

        // Fallback: try to get the current document's directory
        if let documentPath = getXcodeCurrentDocumentPath() {
            // Walk up to find the project root (directory containing .xcodeproj or .xcworkspace)
            var url = URL(fileURLWithPath: documentPath).deletingLastPathComponent()
            for _ in 0..<10 { // Max 10 levels up
                if isProjectRoot(url) {
                    return url
                }
                let parent = url.deletingLastPathComponent()
                if parent == url { break }
                url = parent
            }
            // Return the document's directory as fallback
            return URL(fileURLWithPath: documentPath).deletingLastPathComponent()
        }

        return nil
    }

    /// Check if a directory is a project root (contains .xcodeproj or .xcworkspace)
    private static func isProjectRoot(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    /// Get the path of the currently open Xcode workspace
    private static func getXcodeWorkspacePath() -> String? {
        let script = """
        tell application "Xcode"
            if (count of workspace documents) > 0 then
                set wsDoc to front workspace document
                return path of wsDoc
            end if
        end tell
        return ""
        """
        return runAppleScriptSafely(script)
    }

    /// Get the path of the current document in Xcode
    private static func getXcodeCurrentDocumentPath() -> String? {
        let script = """
        tell application "Xcode"
            if (count of documents) > 0 then
                set frontDoc to front document
                try
                    return path of frontDoc
                on error
                    return ""
                end try
            end if
        end tell
        return ""
        """
        return runAppleScriptSafely(script)
    }

    /// Get the selected text in Xcode
    static func getSelectedText() -> String? {
        guard isXcodeRunning() else { return nil }

        let script = """
        tell application "Xcode"
            set selectedText to selected text of front source document
            return selectedText
        end tell
        """
        return runAppleScriptSafely(script)
    }

    /// Check if Xcode is running
    static func isXcodeRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.apple.dt.Xcode" }
    }

    /// Run an AppleScript safely with timeout and error handling
    /// Returns nil on any error or timeout
    private static func runAppleScriptSafely(_ source: String, timeout: TimeInterval = 2.0) -> String? {
        // Use a semaphore to implement timeout
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        // Run on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async {
            result = executeAppleScript(source)
            semaphore.signal()
        }

        // Wait with timeout
        let waitResult = semaphore.wait(timeout: .now() + timeout)

        if waitResult == .timedOut {
            print("AppleScript timed out")
            return nil
        }

        return result
    }

    /// Execute AppleScript and return result (internal, runs on calling thread)
    private static func executeAppleScript(_ source: String) -> String? {
        // Wrap in autorelease pool for safety
        return autoreleasepool {
            var error: NSDictionary?

            guard let script = NSAppleScript(source: source) else {
                print("Failed to create AppleScript")
                return nil
            }

            let result = script.executeAndReturnError(&error)

            if let error = error {
                // Don't print error for common cases like "not authorized"
                if let errorNumber = error[NSAppleScript.errorNumber] as? Int,
                   errorNumber == -1743 { // Not authorized
                    print("AppleScript not authorized - grant permission in System Settings")
                } else {
                    print("AppleScript error: \(error)")
                }
                return nil
            }

            guard let stringValue = result.stringValue, !stringValue.isEmpty else {
                return nil
            }

            return stringValue
        }
    }
}
