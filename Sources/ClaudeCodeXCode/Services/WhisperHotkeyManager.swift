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

    private var applyHotkey: HotKey?       // F1 - Apply whisper
    private var expandHotkey: HotKey?      // F2 - Tell me more
    private var dismissHotkey: HotKey?     // F3 - Dismiss whisper

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

        print("[WhisperHotkeyManager] Hotkeys registered: F1 (apply), F2 (expand), F3 (dismiss)")
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
        // F1 - Apply whisper patch
        applyHotkey = HotKey(key: .f1, modifiers: [])
        applyHotkey?.keyDownHandler = { [weak self] in
            print("[WhisperHotkeyManager] F1 pressed, hasActiveWhisper: \(self?.hasActiveWhisper ?? false)")
            guard let self = self, self.hasActiveWhisper else {
                print("[WhisperHotkeyManager] F1 ignored - no active whisper")
                return
            }

            print("[WhisperHotkeyManager] F1 - applying whisper")
            NotificationCenter.default.post(name: .whisperHotkeyApply, object: nil)
        }
    }

    private func setupExpandHotkey() {
        // F2 - Tell me more
        expandHotkey = HotKey(key: .f2, modifiers: [])
        expandHotkey?.keyDownHandler = { [weak self] in
            print("[WhisperHotkeyManager] F2 pressed, hasActiveWhisper: \(self?.hasActiveWhisper ?? false)")
            guard let self = self, self.hasActiveWhisper else {
                print("[WhisperHotkeyManager] F2 ignored - no active whisper")
                return
            }

            print("[WhisperHotkeyManager] F2 - expanding whisper")
            NotificationCenter.default.post(name: .whisperHotkeyExpand, object: nil)
        }
    }

    private func setupDismissHotkey() {
        // F3 - Dismiss whisper
        dismissHotkey = HotKey(key: .f3, modifiers: [])
        dismissHotkey?.keyDownHandler = { [weak self] in
            print("[WhisperHotkeyManager] F3 pressed, hasActiveWhisper: \(self?.hasActiveWhisper ?? false)")
            guard let self = self, self.hasActiveWhisper else {
                print("[WhisperHotkeyManager] F3 ignored - no active whisper")
                return
            }

            print("[WhisperHotkeyManager] F3 - dismissing whisper")
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
