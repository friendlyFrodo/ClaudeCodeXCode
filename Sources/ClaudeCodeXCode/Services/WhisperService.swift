import Foundation
import Combine
import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    /// Posted when user wants to expand a whisper (tell me more)
    static let expandWhisper = Notification.Name("com.claudecodexcode.expandWhisper")
}

// MARK: - Whisper Service

/// Main orchestrator for the AI pair programmer whisper system
/// Coordinates context tracking, Haiku API calls, and whisper display
@MainActor
final class WhisperService: ObservableObject {
    // MARK: - Published State

    /// The current whisper being displayed (nil if none)
    @Published private(set) var currentWhisper: Whisper?

    /// Whether whispers are enabled
    @Published var isEnabled: Bool = true

    /// Whether the service is currently processing
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Dependencies

    let contextTracker: ContextTracker
    private let haikuClient: HaikuClient
    private let xcodeWatcher: XcodeWatcher
    private let rateLimiter: WhisperRateLimiter

    // MARK: - Internal State

    private var debounceTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?

    /// Debounce interval before requesting a whisper (seconds)
    /// Very short since we only trigger on file saves now
    private let debounceInterval: TimeInterval = 0.1

    /// Auto-dismiss whispers after this many seconds
    private let autoDismissInterval: TimeInterval = 15.0

    /// Minimum time whisper must be visible (prevents accidental dismiss)
    private var whisperShownAt: Date?

    // MARK: - Initialization

    init() {
        self.contextTracker = ContextTracker()
        self.haikuClient = HaikuClient()
        self.rateLimiter = WhisperRateLimiter()
        self.xcodeWatcher = XcodeWatcher(contextTracker: contextTracker)

        // Wire up context change handler
        xcodeWatcher.onContextChange = { [weak self] context in
            Task { @MainActor in
                self?.handleContextChange(context)
            }
        }
    }

    // MARK: - Start/Stop

    /// Start the whisper service
    func start(projectRoot: String? = nil) {
        xcodeWatcher.start(projectRoot: projectRoot)
        print("[WhisperService] Started")
    }

    /// Stop the whisper service
    func stop() {
        xcodeWatcher.stop()
        debounceTask?.cancel()
        autoDismissTask?.cancel()
        print("[WhisperService] Stopped")
    }

    // MARK: - Context Change Handling

    private func handleContextChange(_ context: CodeContext) {
        print("[WhisperService] handleContextChange called - enabled: \(isEnabled), file: \(context.currentFileName ?? "nil")")

        guard isEnabled else {
            print("[WhisperService] Whispers disabled, skipping")
            return
        }

        // Cancel any pending whisper request
        debounceTask?.cancel()

        // Debounce to avoid rapid-fire requests
        debounceTask = Task {
            print("[WhisperService] Debounce started, waiting \(debounceInterval)s...")

            // Wait for user to stop making changes
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))

            guard !Task.isCancelled else {
                print("[WhisperService] Debounce cancelled (new change came in)")
                return
            }

            // Check rate limiting (unless critical)
            let canWhisper = context.isCriticalChange || rateLimiter.canWhisper()
            guard canWhisper else {
                print("[WhisperService] Rate limited, skipping whisper (wait \(rateLimiter.timeUntilNextWhisper)s)")
                return
            }

            print("[WhisperService] Requesting whisper from Haiku...")
            await requestWhisper(for: context)
        }
    }

    private func requestWhisper(for context: CodeContext) async {
        isProcessing = true
        defer { isProcessing = false }

        print("[WhisperService] Calling Haiku API...")
        print("[WhisperService] Context file: \(context.currentFile ?? "nil")")

        do {
            if let whisper = try await haikuClient.getWhisper(context: context) {
                print("[WhisperService] Got whisper: \(whisper.message)")
                if let patch = whisper.patch {
                    print("[WhisperService] Patch included: file=\(patch.filePath)")
                }
                showWhisper(whisper)
                rateLimiter.didWhisper()
            } else {
                print("[WhisperService] Haiku returned null whisper (nothing to say)")
            }
        } catch {
            print("[WhisperService] ERROR from Haiku: \(error)")
        }
    }

    // MARK: - Whisper Display

    private func showWhisper(_ whisper: Whisper) {
        // Cancel any pending auto-dismiss
        autoDismissTask?.cancel()

        // Record when whisper is shown
        whisperShownAt = Date()

        // Show the whisper
        withAnimation(.easeInOut(duration: 0.3)) {
            currentWhisper = whisper
        }

        // Notify hotkey manager that whisper is visible
        NotificationCenter.default.post(
            name: .whisperVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": true]
        )

        print("[WhisperService] Showing whisper: \(whisper.message)")

        // Schedule auto-dismiss
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoDismissInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            // Only dismiss if it's still the same whisper
            if self.currentWhisper?.id == whisper.id {
                print("[WhisperService] Auto-dismissing after \(autoDismissInterval)s")
                self.dismissWhisper()
            }
        }
    }

    // MARK: - Whisper Actions

    /// Apply the current whisper's patch (⌘Y)
    /// Returns true if patch was applied successfully
    @discardableResult
    func applyWhisper() -> Bool {
        guard let whisper = currentWhisper, let patch = whisper.patch else {
            print("[WhisperService] No patch to apply")
            dismissWhisper()
            return false
        }

        print("[WhisperService] Attempting to apply patch:")
        print("[WhisperService]   File: \(patch.filePath)")
        print("[WhisperService]   Old code: \(patch.oldCode.prefix(100))...")
        print("[WhisperService]   New code: \(patch.newCode.prefix(100))...")

        let result = CodePatcher.apply(patch)

        switch result {
        case .success:
            print("[WhisperService] Patch applied successfully")
            dismissWhisper()
            return true
        case .fileNotFound:
            print("[WhisperService] Patch failed: file not found at '\(patch.filePath)'")
            print("[WhisperService] File exists: \(FileManager.default.fileExists(atPath: patch.filePath))")
        case .codeNotFound:
            print("[WhisperService] Patch failed: code not found (file may have changed)")
        case .writeError(let error):
            print("[WhisperService] Patch failed: \(error)")
        }

        dismissWhisper()
        return false
    }

    /// Expand the current whisper (tell me more) (F2)
    func expandWhisper() {
        guard let whisper = currentWhisper else { return }

        // Build a detailed prompt with context (no redundant "Tell me more")
        var prompt = "\"\(whisper.message)\""

        // Add file context if available
        if let patch = whisper.patch {
            let fileName = (patch.filePath as NSString).lastPathComponent
            prompt += "\n\nFile: \(fileName)"

            // Add code context
            if !patch.oldCode.isEmpty {
                prompt += "\n\nCode:\n\(patch.oldCode)"
            }
        } else if let currentFile = contextTracker.currentFile {
            let fileName = (currentFile as NSString).lastPathComponent
            prompt += "\n\nFile: \(fileName)"
        }

        prompt += "\n\nExplain this and suggest how to fix it."

        // Post notification for the terminal to pick up
        NotificationCenter.default.post(
            name: .expandWhisper,
            object: nil,
            userInfo: ["message": prompt]
        )

        print("[WhisperService] Expanding whisper with context")
        dismissWhisper()
    }

    /// Dismiss the current whisper (⌘N)
    func dismissWhisper(caller: String = #function) {
        // Debug: track who's calling dismiss
        let timeSinceShown = whisperShownAt.map { Date().timeIntervalSince($0) } ?? 0
        print("[WhisperService] dismissWhisper called by: \(caller), whisper age: \(String(format: "%.1f", timeSinceShown))s")

        // Guard: if whisper was just shown (< 1 second), ignore dismiss
        // This prevents race conditions and accidental dismissals
        if timeSinceShown < 1.0 && timeSinceShown > 0 {
            print("[WhisperService] Ignoring dismiss - whisper too new (\(String(format: "%.1f", timeSinceShown))s)")
            return
        }

        autoDismissTask?.cancel()
        whisperShownAt = nil

        withAnimation(.easeOut(duration: 0.2)) {
            currentWhisper = nil
        }

        // Notify hotkey manager that whisper is no longer visible
        NotificationCenter.default.post(
            name: .whisperVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": false]
        )

        print("[WhisperService] Whisper dismissed")
    }

    // MARK: - Manual Trigger (for testing)

    /// Manually trigger a whisper request (for testing)
    func triggerWhisperNow() {
        let context = contextTracker.currentContext
        Task {
            await requestWhisper(for: context)
        }
    }
}

// MARK: - Rate Limiter

/// Limits how frequently whispers can appear
final class WhisperRateLimiter {
    private var lastWhisperTime: Date?

    /// Minimum interval between whispers (seconds)
    /// Set to 0 since whispers are now triggered on manual file saves
    var minimumInterval: TimeInterval = 0

    /// Check if enough time has passed for a new whisper
    func canWhisper() -> Bool {
        guard let last = lastWhisperTime else {
            return true
        }
        return Date().timeIntervalSince(last) >= minimumInterval
    }

    /// Record that a whisper was shown
    func didWhisper() {
        lastWhisperTime = Date()
    }

    /// Reset the rate limiter
    func reset() {
        lastWhisperTime = nil
    }

    /// Time until next whisper is allowed (seconds), or 0 if allowed now
    var timeUntilNextWhisper: TimeInterval {
        guard let last = lastWhisperTime else {
            return 0
        }
        let elapsed = Date().timeIntervalSince(last)
        return max(0, minimumInterval - elapsed)
    }
}
