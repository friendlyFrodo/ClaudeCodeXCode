import Foundation
import AppKit
import CoreGraphics

/// Observes Xcode's visibility state and notifies when it changes
/// Used to show/hide the companion panel when Xcode is minimized/restored
final class XcodeVisibilityObserver {
    /// Callback when Xcode visibility changes
    var onVisibilityChanged: ((Bool) -> Void)?

    /// Current visibility state
    private(set) var isXcodeVisible: Bool = false

    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?

    /// Xcode's bundle identifier
    private let xcodeBundleID = "com.apple.dt.Xcode"

    init() {}

    deinit {
        stop()
    }

    /// Start observing Xcode visibility
    func start() {
        // Initial check
        isXcodeVisible = checkXcodeHasVisibleWindows()

        // Observe app activation/deactivation
        let activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
        workspaceObservers.append(activateObserver)

        let deactivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppDeactivation(notification)
        }
        workspaceObservers.append(deactivateObserver)

        // Observe app hide/unhide
        let hideObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppHide(notification)
        }
        workspaceObservers.append(hideObserver)

        let unhideObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppUnhide(notification)
        }
        workspaceObservers.append(unhideObserver)

        // Poll periodically to catch minimize/restore (not covered by notifications)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkVisibilityChange()
        }

        print("[XcodeVisibilityObserver] Started, Xcode visible: \(isXcodeVisible)")
    }

    /// Stop observing
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        print("[XcodeVisibilityObserver] Stopped")
    }

    // MARK: - Notification Handlers

    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == xcodeBundleID else { return }

        // Xcode activated - check if it has visible windows
        checkVisibilityChange()
    }

    private func handleAppDeactivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == xcodeBundleID else { return }

        // Xcode deactivated - still check windows (it might still be visible)
        checkVisibilityChange()
    }

    private func handleAppHide(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == xcodeBundleID else { return }

        // Xcode hidden (Cmd+H)
        updateVisibility(false)
    }

    private func handleAppUnhide(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == xcodeBundleID else { return }

        // Xcode unhidden
        checkVisibilityChange()
    }

    // MARK: - Visibility Check

    private func checkVisibilityChange() {
        let visible = checkXcodeHasVisibleWindows()
        if visible != isXcodeVisible {
            updateVisibility(visible)
        }
    }

    private func updateVisibility(_ visible: Bool) {
        isXcodeVisible = visible
        print("[XcodeVisibilityObserver] Xcode visibility changed: \(visible)")
        onVisibilityChanged?(visible)
    }

    /// Check if Xcode has any visible (non-minimized) windows
    private func checkXcodeHasVisibleWindows() -> Bool {
        // First check if Xcode is running
        let xcodeApps = NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleID)
        guard let xcode = xcodeApps.first, !xcode.isTerminated else {
            return false
        }

        // Check if Xcode is hidden
        if xcode.isHidden {
            return false
        }

        // Get all windows and check if Xcode has visible ones
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID] as? pid_t,
                  ownerPID == xcode.processIdentifier else { continue }

            // Check if this is a regular window (not a menu or other UI element)
            if let layer = window[kCGWindowLayer] as? Int, layer == 0 {
                // Layer 0 = normal window, and it's on screen = visible
                return true
            }
        }

        return false
    }
}
