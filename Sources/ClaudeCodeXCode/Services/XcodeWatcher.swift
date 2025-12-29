import Foundation
import AppKit
import CoreServices

/// Monitors Xcode for file changes and user activity
/// Combines AppleScript polling (current document) with FSEvents (file saves)
@MainActor
final class XcodeWatcher: ObservableObject {
    /// Callback when a significant context change is detected
    var onContextChange: ((CodeContext) -> Void)?

    /// The context tracker to update
    private let contextTracker: ContextTracker

    /// File watcher for project directory
    private var fileWatcher: ProjectFileWatcher?

    /// Timer for polling Xcode's current document
    private var pollingTimer: Timer?

    /// Polling interval in seconds (must be > debounce interval to avoid cancellation loops)
    private let pollingInterval: TimeInterval = 5.0

    /// Last detected file path (to avoid duplicate triggers)
    private var lastDetectedFile: String?

    /// Last content hash (to detect changes within same file)
    private var lastContentHash: Int?

    /// Previous file content (for diff computation)
    private var previousContent: String?

    /// When the previous content was captured
    private var previousContentTime: Date?

    /// Project root directory being watched
    private var projectRoot: String?

    /// Last file content hash (for detecting changes)
    private var fileContentHashes: [String: Int] = [:]

    /// Previous context for change detection
    private var previousContext: CodeContext?

    init(contextTracker: ContextTracker) {
        self.contextTracker = contextTracker
    }

    deinit {
        stop()
    }

    // MARK: - Start/Stop

    /// Start watching Xcode
    func start(projectRoot: String? = nil) {
        self.projectRoot = projectRoot

        // Start polling Xcode for current document
        startPolling()

        // Start watching project files for saves
        if let root = projectRoot {
            startFileWatching(at: root)
        }

        print("[XcodeWatcher] Started watching")
    }

    /// Stop watching
    nonisolated func stop() {
        Task { @MainActor in
            self.pollingTimer?.invalidate()
            self.pollingTimer = nil
            self.fileWatcher?.stop()
            self.fileWatcher = nil
            print("[XcodeWatcher] Stopped watching")
        }
    }

    // MARK: - Xcode Polling

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollXcode()
            }
        }
        // Also poll immediately
        pollXcode()
    }

    private func pollXcode() {
        // Get current document from Xcode via AppleScript
        getCurrentXcodeDocument { [weak self] filePath in
            Task { @MainActor in
                guard let self = self else { return }

                // Only process if we got a valid source file path
                guard let path = filePath, self.isSourceFile(path) else {
                    return
                }

                // Read file content
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                    return
                }

                let contentHash = content.hashValue
                let isNewFile = path != self.lastDetectedFile
                let isContentChanged = contentHash != self.lastContentHash

                // Only trigger if file changed OR content changed
                guard isNewFile || isContentChanged else {
                    return
                }

                print("[XcodeWatcher] Change detected - file: \(isNewFile ? "NEW" : "same"), content: \(isContentChanged ? "CHANGED" : "same")")

                let fileName = (path as NSString).lastPathComponent

                // Compute diff if we have previous content for this file
                var contextMessage = ""

                if isContentChanged && !isNewFile, let prev = self.previousContent {
                    // Compute simple diff
                    let diff = self.computeDiff(old: prev, new: content)
                    if !diff.isEmpty {
                        contextMessage = "RECENT CHANGES in \(fileName):\n\(diff)\n\n"
                    }
                }

                // Always include full file content (truncate at 200 lines for very large files)
                let lines = content.components(separatedBy: .newlines)
                let maxLines = min(lines.count, 200)
                let fullContent = lines.prefix(maxLines).joined(separator: "\n")
                contextMessage += "FULL FILE \(fileName) (\(lines.count) lines):\n\(fullContent)"

                if lines.count > 200 {
                    contextMessage += "\n... [truncated, \(lines.count - 200) more lines]"
                }

                // Update state
                self.lastDetectedFile = path
                self.lastContentHash = contentHash
                self.previousContent = content
                self.previousContentTime = Date()
                self.contextTracker.setCurrentFile(path)
                self.contextTracker.recordCodeChange(contextMessage)

                // Check if context changed significantly
                self.checkForSignificantChange()
            }
        }
    }

    /// Compute a simple diff between old and new content
    private func computeDiff(old: String, new: String) -> String {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)

        var additions: [(Int, String)] = []
        var deletions: [(Int, String)] = []

        // Simple line-by-line comparison
        let maxLines = max(oldLines.count, newLines.count)
        for i in 0..<maxLines {
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil

            if oldLine != newLine {
                if let old = oldLine, !old.trimmingCharacters(in: .whitespaces).isEmpty {
                    deletions.append((i + 1, old))
                }
                if let new = newLine, !new.trimmingCharacters(in: .whitespaces).isEmpty {
                    additions.append((i + 1, new))
                }
            }
        }

        // Build diff string (limit to 20 changes to avoid huge diffs)
        var diff = ""
        for (line, content) in deletions.prefix(10) {
            diff += "- L\(line): \(content)\n"
        }
        for (line, content) in additions.prefix(10) {
            diff += "+ L\(line): \(content)\n"
        }

        if deletions.count > 10 || additions.count > 10 {
            diff += "... [\(deletions.count) deletions, \(additions.count) additions total]\n"
        }

        return diff
    }

    /// Get the current document path from Xcode via AppleScript
    private func getCurrentXcodeDocument(completion: @escaping (String?) -> Void) {
        // This script tries to get the file path from Xcode's front window
        // It looks for source documents (not project documents)
        let script = """
        tell application "System Events"
            if not (exists process "Xcode") then
                return ""
            end if
        end tell

        tell application "Xcode"
            try
                -- Try to get the file from the front window's document
                set frontWindow to front window
                set windowName to name of frontWindow

                -- Check all source documents for a matching name
                repeat with doc in source documents
                    try
                        set docPath to path of doc
                        set docName to name of doc
                        if windowName contains docName then
                            return docPath
                        end if
                    end try
                end repeat

                -- Fallback: return first source document if any
                if (count of source documents) > 0 then
                    return path of first source document
                end if

                return ""
            on error
                return ""
            end try
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&error)
                let path = result.stringValue
                DispatchQueue.main.async {
                    completion(path?.isEmpty == false ? path : nil)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - File Watching (FSEvents)

    private func startFileWatching(at path: String) {
        fileWatcher = ProjectFileWatcher(rootPath: path) { [weak self] changedFile in
            Task { @MainActor in
                self?.handleFileChange(changedFile)
            }
        }
        fileWatcher?.start()
    }

    private func handleFileChange(_ filePath: String) {
        // Filter out noise directories (like .claude-flow, .git, node_modules, etc.)
        let noisePatterns = [".claude-flow", ".git", "node_modules", ".build", "DerivedData", ".swiftpm"]
        for pattern in noisePatterns {
            if filePath.contains(pattern) {
                return  // Silently ignore
            }
        }

        // Only care about source files
        guard isSourceFile(filePath) else { return }

        print("[XcodeWatcher] File changed: \(filePath)")

        // Read file and compute diff/change
        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            let currentHash = content.hashValue

            if let previousHash = fileContentHashes[filePath], previousHash != currentHash {
                // Content changed - capture actual code snippet for context
                let lines = content.components(separatedBy: .newlines)
                let preview = lines.prefix(20).joined(separator: "\n")
                let fileName = (filePath as NSString).lastPathComponent
                contextTracker.recordCodeChange("Changed \(fileName):\n\(preview)")
            }

            fileContentHashes[filePath] = currentHash
        }

        // Check for significant change
        checkForSignificantChange()
    }

    private func isSourceFile(_ path: String) -> Bool {
        let sourceExtensions = ["swift", "m", "mm", "h", "c", "cpp", "cc", "py", "js", "ts", "json", "yaml", "yml"]
        let ext = (path as NSString).pathExtension.lowercased()
        return sourceExtensions.contains(ext)
    }

    // MARK: - Change Detection

    private func checkForSignificantChange() {
        let context = contextTracker.currentContext

        if context.isSignificantChange(from: previousContext) {
            print("[XcodeWatcher] Significant change - file: \(context.currentFileName ?? "nil")")
            if let callback = onContextChange {
                print("[XcodeWatcher] Calling onContextChange callback...")
                callback(context)
                print("[XcodeWatcher] Callback returned")
            } else {
                print("[XcodeWatcher] WARNING: onContextChange is nil!")
            }
        }

        previousContext = context
    }
}

// MARK: - Project File Watcher (FSEvents wrapper)

/// Watches a project directory for file changes using FSEvents
final class ProjectFileWatcher {
    typealias ChangeHandler = (String) -> Void

    private var streamRef: FSEventStreamRef?
    private let rootPath: String
    private let onChange: ChangeHandler
    private var isRunning = false

    init(rootPath: String, onChange: @escaping ChangeHandler) {
        self.rootPath = rootPath
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }

        // Verify directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDir), isDir.boolValue else {
            print("[ProjectFileWatcher] Invalid directory: \(rootPath)")
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, eventFlags, _ in
            guard let info = clientInfo else { return }
            let watcher = Unmanaged<ProjectFileWatcher>.fromOpaque(info).takeUnretainedValue()

            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

            for (index, path) in paths.enumerated() {
                let flag = flags[index]

                // Check for file modifications (not just directory changes)
                let isModified = (flag & UInt32(kFSEventStreamEventFlagItemModified)) != 0
                let isCreated = (flag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
                let isFile = (flag & UInt32(kFSEventStreamEventFlagItemIsFile)) != 0

                if (isModified || isCreated) && isFile {
                    DispatchQueue.main.async {
                        watcher.onChange(path)
                    }
                }
            }
        }

        streamRef = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // 500ms latency
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer
            )
        )

        guard let stream = streamRef else {
            print("[ProjectFileWatcher] Failed to create FSEventStream")
            return
        }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        if FSEventStreamStart(stream) {
            isRunning = true
            print("[ProjectFileWatcher] Started watching: \(rootPath)")
        } else {
            print("[ProjectFileWatcher] Failed to start FSEventStream")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
    }

    func stop() {
        guard isRunning, let stream = streamRef else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
        isRunning = false
        print("[ProjectFileWatcher] Stopped")
    }
}
