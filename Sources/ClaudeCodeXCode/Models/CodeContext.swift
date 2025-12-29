import Foundation

/// Context about what the user is currently working on in Xcode
struct CodeContext {
    /// The currently open file in Xcode
    let currentFile: String?

    /// Last 3 files touched since last prompt (most recent first)
    let recentFiles: [String]

    /// The function/method at the cursor position (if detectable)
    let currentFunction: String?

    /// Recent code change (diff or new code)
    let codeChange: String?

    /// Current build status
    let buildStatus: BuildStatus?

    /// Language of the current file
    var language: String {
        guard let file = currentFile else { return "swift" }
        let ext = (file as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "m", "mm": return "objective-c"
        case "h": return "c"  // Could be ObjC or C
        case "c": return "c"
        case "cpp", "cc", "cxx": return "cpp"
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "md": return "markdown"
        default: return "text"
        }
    }

    /// Get just the filename from the current file path
    var currentFileName: String? {
        guard let file = currentFile else { return nil }
        return (file as NSString).lastPathComponent
    }

    /// Get filenames from recent files
    var recentFileNames: [String] {
        recentFiles.map { ($0 as NSString).lastPathComponent }
    }

    init(
        currentFile: String? = nil,
        recentFiles: [String] = [],
        currentFunction: String? = nil,
        codeChange: String? = nil,
        buildStatus: BuildStatus? = nil
    ) {
        self.currentFile = currentFile
        self.recentFiles = recentFiles
        self.currentFunction = currentFunction
        self.codeChange = codeChange
        self.buildStatus = buildStatus
    }
}

// MARK: - Build Status

enum BuildStatus: Equatable {
    case success
    case failed(errors: [String])
    case building

    var description: String {
        switch self {
        case .success:
            return "Build succeeded"
        case .failed(let errors):
            return "Build failed: \(errors.count) error(s)"
        case .building:
            return "Building..."
        }
    }
}

// MARK: - Context Change Detection

extension CodeContext {
    /// Check if this context represents a significant change worth potentially whispering about
    func isSignificantChange(from previous: CodeContext?) -> Bool {
        guard let previous = previous else {
            // First context - significant if we have a file
            return currentFile != nil
        }

        // File switched
        if currentFile != previous.currentFile && currentFile != nil {
            return true
        }

        // Build status changed to failed
        if case .failed = buildStatus, previous.buildStatus != buildStatus {
            return true
        }

        // Code change present and substantial
        if let change = codeChange, change.count > 30 {
            return true
        }

        return false
    }

    /// Check if this is a critical change that should bypass rate limiting
    var isCriticalChange: Bool {
        // Build failures are critical
        if case .failed = buildStatus {
            return true
        }

        // Could add more critical patterns here:
        // - Force unwrap detected
        // - Potential crash patterns
        // - Security issues

        return false
    }
}
