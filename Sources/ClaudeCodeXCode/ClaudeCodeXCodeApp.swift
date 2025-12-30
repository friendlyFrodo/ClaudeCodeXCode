import SwiftUI
import AppKit

@main
struct ClaudeCodeXCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - we manage windows manually via AppDelegate
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingPanel: FloatingPanel?
    var settingsWindow: NSWindow?
    private var xcodeVisibilityObserver: XcodeVisibilityObserver?
    private var statusItem: NSStatusItem?

    /// Track if panel was manually hidden (vs auto-hidden due to Xcode)
    private var panelManuallyHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up global hotkeys for whisper actions
        WhisperHotkeyManager.shared.setup()

        // Set up the application menu
        setupMenu()

        // Create and show the floating panel
        floatingPanel = FloatingPanel()
        floatingPanel?.show()

        // Set up menu bar icon
        setupStatusBar()

        // Set up Xcode visibility observer to show/hide panel with Xcode
        setupXcodeVisibilityObserver()

        // Hide dock icon (optional - comment out if you want dock presence)
        // NSApp.setActivationPolicy(.accessory)
    }

    private func setupXcodeVisibilityObserver() {
        xcodeVisibilityObserver = XcodeVisibilityObserver()
        xcodeVisibilityObserver?.onVisibilityChanged = { [weak self] isVisible in
            guard let self = self, let panel = self.floatingPanel, !self.panelManuallyHidden else { return }

            if isVisible {
                // Restore from dock with animation
                panel.deminiaturize(nil)
            } else {
                // Minimize to dock with animation (genie/scale effect)
                panel.miniaturize(nil)
            }
        }

        // Snap panel to Xcode when its window frame changes
        xcodeVisibilityObserver?.onFrameChanged = { [weak self] xcodeFrame in
            guard let panel = self?.floatingPanel, !self!.panelManuallyHidden else { return }
            panel.snapToXcode(xcodeFrame: xcodeFrame)
        }

        xcodeVisibilityObserver?.start()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude Code")
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    @objc private func togglePanel() {
        guard let panel = floatingPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            panelManuallyHidden = true
        } else {
            panel.makeKeyAndOrderFront(nil)
            panelManuallyHidden = false
        }
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit Claude Code",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appMenu.addItem(NSMenuItem(title: "About Claude Code", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Window menu (for standard window management)
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.close), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up observers
        xcodeVisibilityObserver?.stop()

        // Clean up hotkeys
        WhisperHotkeyManager.shared.tearDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running even when panel is closed
    }

    /// Open settings and bring to front (called from menu or hotkey)
    @objc func openSettings() {
        // Hide the floating panel temporarily so it doesn't interfere with focus
        floatingPanel?.orderOut(nil)

        // If settings window already exists, just bring it to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create settings window
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()

        // When settings closes, restore floating panel
        window.onClose = { [weak self] in
            self?.floatingPanel?.makeKeyAndOrderFront(nil)
        }

        // Show and activate
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Store reference
        settingsWindow = window
    }
}

/// Custom window class that properly handles becoming key
class SettingsWindow: NSWindow {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func close() {
        onClose?()
        super.close()
    }
}
