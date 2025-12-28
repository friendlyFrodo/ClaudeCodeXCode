import SwiftUI
import AppKit

@main
struct ClaudeCodeXCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingPanel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create and show the floating panel
        floatingPanel = FloatingPanel()
        floatingPanel?.show()

        // Hide dock icon (optional - comment out if you want dock presence)
        // NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running even when panel is closed
    }
}
