import SwiftUI
import AppKit

/// A floating panel window that stays visible alongside Xcode
class FloatingPanel: NSPanel {
    private var hostingView: NSHostingView<MainContentView>?

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
    }

    private func configure() {
        // Floating behavior
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ]

        // Xcode-like dark title bar appearance
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        titlebarAppearsTransparent = false
        titleVisibility = .visible

        // Style the title bar like Xcode
        if let titlebarView = standardWindowButton(.closeButton)?.superview?.superview {
            titlebarView.wantsLayer = true
            titlebarView.layer?.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0).cgColor
        }

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

        // Title for accessibility
        title = "Claude Code"
    }

    private func setupContent() {
        let contentView = MainContentView()
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.translatesAutoresizingMaskIntoConstraints = false

        self.contentView = hostingView
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
