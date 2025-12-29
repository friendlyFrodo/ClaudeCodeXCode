import Foundation
import CoreServices

/// Watches directories for file changes using FSEvents
/// Used to detect when Xcode theme files are modified
final class ThemeFileWatcher {
    typealias ChangeHandler = () -> Void

    private var streamRef: FSEventStreamRef?
    private let pathsToWatch: [String]
    private let callback: ChangeHandler
    private var isRunning = false

    /// Initialize a file watcher
    /// - Parameters:
    ///   - paths: Directory paths to watch
    ///   - onChange: Callback invoked when any file changes
    init(watching paths: [String], onChange: @escaping ChangeHandler) {
        self.pathsToWatch = paths
        self.callback = onChange
    }

    deinit {
        stop()
    }

    /// Start watching for file changes
    func start() {
        guard !isRunning else { return }

        // Filter to only existing directories
        let validPaths = pathsToWatch.filter { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }

        guard !validPaths.isEmpty else {
            print("[ThemeFileWatcher] No valid directories to watch")
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallbackInfo, numEvents, eventPaths, eventFlags, _ in
            guard let info = clientCallbackInfo else { return }
            let watcher = Unmanaged<ThemeFileWatcher>.fromOpaque(info).takeUnretainedValue()

            // Check if any events are relevant (file modifications, not just metadata)
            let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
            let hasRelevantChange = flags.contains { flag in
                let isItemModified = (flag & UInt32(kFSEventStreamEventFlagItemModified)) != 0
                let isItemCreated = (flag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
                let isItemRemoved = (flag & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
                let isItemRenamed = (flag & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
                return isItemModified || isItemCreated || isItemRemoved || isItemRenamed
            }

            if hasRelevantChange {
                DispatchQueue.main.async {
                    watcher.callback()
                }
            }
        }

        streamRef = FSEventStreamCreate(
            nil,
            callback,
            &context,
            validPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // Latency: 1 second debounce
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer
            )
        )

        guard let stream = streamRef else {
            print("[ThemeFileWatcher] Failed to create FSEventStream")
            return
        }

        FSEventStreamScheduleWithRunLoop(
            stream,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        if FSEventStreamStart(stream) {
            isRunning = true
            print("[ThemeFileWatcher] Started watching: \(validPaths)")
        } else {
            print("[ThemeFileWatcher] Failed to start FSEventStream")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
    }

    /// Stop watching for file changes
    func stop() {
        guard isRunning, let stream = streamRef else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
        isRunning = false
        print("[ThemeFileWatcher] Stopped watching")
    }
}
