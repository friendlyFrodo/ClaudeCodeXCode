import Foundation
import HotKey
import AppKit

// MARK: - Notification Names for Whisper Actions

extension Notification.Name {
    /// Posted when ⌘Y is pressed to apply a whisper
    static let whisperHotkeyApply = Notification.Name("com.claudecodexcode.whisperHotkeyApply")
    /// Posted when ⌘? is pressed to expand a whisper
    static let whisperHotkeyExpand = Notification.Name("com.claudecodexcode.whisperHotkeyExpand")
    /// Posted when ⌘N is pressed to dismiss a whisper
    static let whisperHotkeyDismiss = Notification.Name("com.claudecodexcode.whisperHotkeyDismiss")
    /// Posted by WhisperService when whisper visibility changes
    static let whisperVisibilityChanged = Notification.Name("com.claudecodexcode.whisperVisibilityChanged")
}

/// Manages global hotkeys for whisper actions
/// These hotkeys work from Xcode without focusing the Claude panel
/// Uses NotificationCenter for decoupled communication with SwiftUI views
final class WhisperHotkeyManager {
    // MARK: - Singleton

    static let shared = WhisperHotkeyManager()

    // MARK: - Hotkeys

    private var applyHotkey: HotKey?       // ⌘Y - Apply whisper
    private var expandHotkey: HotKey?      // ⌘? (⌘⇧/) - Tell me more
    private var dismissHotkey: HotKey?     // ⌘N - Dismiss whisper

    // MARK: - State

    /// Track if there's an active whisper (updated via notification)
    private var hasActiveWhisper: Bool = false

    private var visibilityObserver: NSObjectProtocol?

    // MARK: - Init

    private init() {
        // Listen for whisper visibility changes
        visibilityObserver = NotificationCenter.default.addObserver(
            forName: .whisperVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let isVisible = notification.userInfo?["isVisible"] as? Bool {
                self?.hasActiveWhisper = isVisible
            }
        }
    }

    deinit {
        if let observer = visibilityObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    func setup() {
        setupApplyHotkey()
        setupExpandHotkey()
        setupDismissHotkey()

        print("[WhisperHotkeyManager] Hotkeys registered: ⌘Y (apply), ⌘⇧/ (expand), ⌘N (dismiss)")
    }

    /// Tear down all hotkeys
    func tearDown() {
        applyHotkey = nil
        expandHotkey = nil
        dismissHotkey = nil
        print("[WhisperHotkeyManager] Hotkeys unregistered")
    }

    // MARK: - Individual Hotkey Setup

    private func setupApplyHotkey() {
        // ⌘Y - Apply whisper patch
        applyHotkey = HotKey(key: .y, modifiers: [.command])
        applyHotkey?.keyDownHandler = { [weak self] in
            guard let self = self, self.hasActiveWhisper else { return }

            print("[WhisperHotkeyManager] ⌘Y pressed - applying whisper")
            NotificationCenter.default.post(name: .whisperHotkeyApply, object: nil)
        }
    }

    private func setupExpandHotkey() {
        // ⌘⇧/ (⌘?) - Tell me more
        expandHotkey = HotKey(key: .slash, modifiers: [.command, .shift])
        expandHotkey?.keyDownHandler = { [weak self] in
            guard let self = self, self.hasActiveWhisper else { return }

            print("[WhisperHotkeyManager] ⌘? pressed - expanding whisper")
            NotificationCenter.default.post(name: .whisperHotkeyExpand, object: nil)
        }
    }

    private func setupDismissHotkey() {
        // ⌘N - Dismiss whisper
        // Note: This might conflict with "New" in some apps
        // We only activate it when there's an active whisper
        dismissHotkey = HotKey(key: .n, modifiers: [.command])
        dismissHotkey?.keyDownHandler = { [weak self] in
            guard let self = self, self.hasActiveWhisper else { return }

            print("[WhisperHotkeyManager] ⌘N pressed - dismissing whisper")
            NotificationCenter.default.post(name: .whisperHotkeyDismiss, object: nil)
        }
    }

    // MARK: - Dynamic Enable/Disable

    /// Temporarily disable hotkeys (e.g., when app is in background)
    func setEnabled(_ enabled: Bool) {
        applyHotkey?.isPaused = !enabled
        expandHotkey?.isPaused = !enabled
        dismissHotkey?.isPaused = !enabled

        print("[WhisperHotkeyManager] Hotkeys \(enabled ? "enabled" : "disabled")")
    }
}
