import SwiftUI
import AppKit

/// A floating panel window that stays visible alongside Xcode
class FloatingPanel: NSPanel {
    private var hostingView: NSHostingView<MainContentView>?
    private var themeObserver: NSObjectProtocol?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .nonactivatingPanel,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )

        configure()
        setupContent()
        setupThemeObserver()
        applyInitialTheme()
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func configure() {
        // Floating behavior
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ]

        // Make title bar transparent to blend with content (like Xcode)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden  // Hide title text for cleaner look
        isOpaque = false

        // Window behavior
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        // Minimum size
        minSize = NSSize(width: 320, height: 400)

        // Position on right side of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = frame
            let newOrigin = NSPoint(
                x: screenFrame.maxX - windowFrame.width - 20,
                y: screenFrame.midY - windowFrame.height / 2
            )
            setFrameOrigin(newOrigin)
        }

        // Title for accessibility (still set even though hidden)
        title = "Claude Code"
    }

    private func setupContent() {
        let contentView = MainContentView()
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.translatesAutoresizingMaskIntoConstraints = false

        self.contentView = hostingView
    }

    private func setupThemeObserver() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .themeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let theme = notification.userInfo?["theme"] as? Theme {
                self?.applyTheme(theme)
            }
        }
    }

    private func applyInitialTheme() {
        // Read Xcode's IDEAppearance to determine initial theme
        let isDark = isXcodeDarkMode()
        let theme = isDark ? Theme.xcodeDefaultDark : Theme.xcodeDefaultLight
        applyTheme(theme)
    }

    private func isXcodeDarkMode() -> Bool {
        if let xcodeDefaults = UserDefaults(suiteName: "com.apple.dt.Xcode") {
            let ideAppearance = xcodeDefaults.integer(forKey: "IDEAppearance")
            switch ideAppearance {
            case 1: return false  // Light
            case 2: return true   // Dark
            default: break        // System - fall through
            }
        }
        // Fall back to system appearance
        let appearance = NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    private func applyTheme(_ theme: Theme) {
        print("[FloatingPanel] Applying theme: \(theme.name), isDark: \(theme.isDark)")

        // Update window appearance
        appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        backgroundColor = theme.backgroundColor

        // Force redraw
        invalidateShadow()
        displayIfNeeded()
    }

    func show() {
        makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            show()
        }
    }

    // Allow the panel to become key for text input
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }
}
