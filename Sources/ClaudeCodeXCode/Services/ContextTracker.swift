import Foundation
import Combine

/// Tracks the context of what the user is working on
/// Maintains a history of recent files and detects significant changes
@MainActor
final class ContextTracker: ObservableObject {
    /// Maximum number of recent files to track
    private let maxRecentFiles = 3

    /// Current file being edited
    @Published private(set) var currentFile: String?

    /// Recent files (most recent first), excluding current file
    @Published private(set) var recentFiles: [String] = []

    /// The last known code change/diff
    @Published private(set) var lastCodeChange: String?

    /// Current build status
    @Published private(set) var buildStatus: BuildStatus?

    /// Combined context for whisper evaluation
    var currentContext: CodeContext {
        CodeContext(
            currentFile: currentFile,
            recentFiles: recentFiles,
            currentFunction: nil,  // TODO: Implement function detection
            codeChange: lastCodeChange,
            buildStatus: buildStatus
        )
    }

    /// All tracked files (current + recent) for display
    var allTrackedFiles: [String] {
        var files: [String] = []
        if let current = currentFile {
            files.append(current)
        }
        files.append(contentsOf: recentFiles.filter { $0 != currentFile })
        return Array(files.prefix(maxRecentFiles))
    }

    /// Filenames only (for Context Bar display)
    var trackedFileNames: [String] {
        allTrackedFiles.map { ($0 as NSString).lastPathComponent }
    }

    // MARK: - File Tracking

    /// Update the current file being edited
    func setCurrentFile(_ filePath: String?) {
        guard let filePath = filePath, !filePath.isEmpty else { return }

        // Don't update if it's the same file
        guard filePath != currentFile else { return }

        // Move previous current file to recent
        if let previous = currentFile {
            addToRecentFiles(previous)
        }

        currentFile = filePath
        print("[ContextTracker] Current file: \(filePath)")
    }

    /// Add a file to the recent files list
    private func addToRecentFiles(_ filePath: String) {
        // Remove if already in list (will re-add at front)
        recentFiles.removeAll { $0 == filePath }

        // Add to front
        recentFiles.insert(filePath, at: 0)

        // Trim to max size
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
    }

    // MARK: - Code Change Tracking

    /// Record a code change (called when file is saved or significant edit detected)
    func recordCodeChange(_ change: String) {
        lastCodeChange = change
        print("[ContextTracker] Code change recorded: \(change.prefix(50))...")
    }

    /// Clear the last code change (after it's been processed)
    func clearCodeChange() {
        lastCodeChange = nil
    }

    // MARK: - Build Status

    /// Update the build status
    func setBuildStatus(_ status: BuildStatus?) {
        buildStatus = status
        if let status = status {
            print("[ContextTracker] Build status: \(status.description)")
        }
    }

    // MARK: - Reset

    /// Reset context tracking (e.g., after user sends a prompt)
    func resetAfterPrompt() {
        // Keep current file, but clear recent history
        recentFiles.removeAll()
        lastCodeChange = nil
        print("[ContextTracker] Context reset after prompt")
    }

    /// Full reset (e.g., when project changes)
    func fullReset() {
        currentFile = nil
        recentFiles.removeAll()
        lastCodeChange = nil
        buildStatus = nil
        print("[ContextTracker] Full context reset")
    }
}
