import Foundation
import AppKit
import CoreGraphics

/// Observes Xcode's visibility state and notifies when it changes
/// Used to show/hide the companion panel when Xcode is minimized/restored
final class XcodeVisibilityObserver {
    /// Callback when Xcode visibility changes
    var onVisibilityChanged: ((Bool) -> Void)?

    /// Callback when Xcode window frame changes
    var onFrameChanged: ((NSRect) -> Void)?

    /// Current visibility state
    private(set) var isXcodeVisible: Bool = false

    /// Current Xcode window frame (nil if not visible)
    private(set) var xcodeWindowFrame: NSRect?

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
        let result = checkXcodeHasVisibleWindows()
        isXcodeVisible = result.visible
        xcodeWindowFrame = result.frame
        if let frame = result.frame {
            onFrameChanged?(frame)
        }

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

        // Poll periodically to catch minimize/restore and track window position
        // Using 50ms interval for smooth window tracking (~20fps)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
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
        let result = checkXcodeHasVisibleWindows()

        // Check visibility change
        if result.visible != isXcodeVisible {
            updateVisibility(result.visible)
        }

        // Check frame change (only notify if visible and frame changed significantly)
        if let newFrame = result.frame {
            if xcodeWindowFrame == nil || !NSEqualRects(newFrame, xcodeWindowFrame!) {
                xcodeWindowFrame = newFrame
                onFrameChanged?(newFrame)
            }
        } else {
            xcodeWindowFrame = nil
        }
    }

    private func updateVisibility(_ visible: Bool) {
        isXcodeVisible = visible
        print("[XcodeVisibilityObserver] Xcode visibility changed: \(visible)")
        onVisibilityChanged?(visible)
    }

    /// Check if Xcode has any visible (non-minimized) windows and get the main window frame
    private func checkXcodeHasVisibleWindows() -> (visible: Bool, frame: NSRect?) {
        // First check if Xcode is running
        let xcodeApps = NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleID)
        guard let xcode = xcodeApps.first, !xcode.isTerminated else {
            return (false, nil)
        }

        // Check if Xcode is hidden
        if xcode.isHidden {
            return (false, nil)
        }

        // Get all windows and check if Xcode has visible ones
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []

        var largestFrame: NSRect?
        var largestArea: CGFloat = 0

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID] as? pid_t,
                  ownerPID == xcode.processIdentifier else { continue }

            // Check if this is a regular window (not a menu or other UI element)
            if let layer = window[kCGWindowLayer] as? Int, layer == 0 {
                // Extract window bounds
                if let boundsDict = window[kCGWindowBounds] as? [String: CGFloat],
                   let x = boundsDict["X"],
                   let y = boundsDict["Y"],
                   let width = boundsDict["Width"],
                   let height = boundsDict["Height"] {
                    let frame = NSRect(x: x, y: y, width: width, height: height)
                    let area = width * height

                    // Track the largest window (likely the main editor window)
                    if area > largestArea {
                        largestArea = area
                        largestFrame = frame
                    }
                }
            }
        }

        return (largestFrame != nil, largestFrame)
    }
}
