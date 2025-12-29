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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up global hotkeys for whisper actions
        WhisperHotkeyManager.shared.setup()

        // Set up the application menu
        setupMenu()

        // Create and show the floating panel
        floatingPanel = FloatingPanel()
        floatingPanel?.show()

        // Hide dock icon (optional - comment out if you want dock presence)
        // NSApp.setActivationPolicy(.accessory)
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
