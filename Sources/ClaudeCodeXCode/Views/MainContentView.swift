import SwiftUI
import SwiftTerm

/// Main content view with full terminal interface and AI pair programmer features
struct MainContentView: View {
    @StateObject private var claudeService = ClaudeCodeService()
    @StateObject private var themeReader = XcodeThemeReader()
    @StateObject private var whisperService = WhisperService()

    var body: some View {
        VStack(spacing: 0) {
            // Context bar showing files Claude is watching
            ContextBar(
                contextTracker: whisperService.contextTracker,
                isProcessing: whisperService.isProcessing
            )

            Divider()

            // Main terminal view
            TerminalContainerView(
                workingDirectory: claudeService.workingDirectory,
                theme: themeReader.currentTheme,
                onProcessTerminated: { exitCode in
                    claudeService.handleProcessTerminated(exitCode: exitCode)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Whisper bubble (appears when there's a whisper)
            WhisperContainer(
                whisper: whisperService.currentWhisper,
                onApply: { whisperService.applyWhisper() },
                onExpand: { whisperService.expandWhisper() },
                onDismiss: { whisperService.dismissWhisper() }
            )
        }
        .onAppear {
            claudeService.handleProcessStarted()
            // Start whisper service with the project root
            whisperService.start(projectRoot: claudeService.workingDirectory?.path)
        }
        .onDisappear {
            whisperService.stop()
        }
        .background(VisualEffectBlur())
        .preferredColorScheme(themeReader.currentTheme.isDark ? .dark : .light)
        // Handle expand whisper notification
        .onReceive(NotificationCenter.default.publisher(for: .expandWhisper)) { notification in
            handleExpandWhisper(notification)
        }
        // Handle global hotkey notifications
        .onReceive(NotificationCenter.default.publisher(for: .whisperHotkeyApply)) { _ in
            whisperService.applyWhisper()
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperHotkeyExpand)) { _ in
            whisperService.expandWhisper()
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperHotkeyDismiss)) { _ in
            whisperService.dismissWhisper()
        }
    }

    /// Handle the "Tell me more" action by injecting a prompt into the terminal
    private func handleExpandWhisper(_ notification: Notification) {
        guard let message = notification.userInfo?["message"] as? String else { return }

        // The prompt to inject
        let prompt = "Tell me more about: \"\(message)\""

        // Post notification for terminal to handle
        NotificationCenter.default.post(
            name: .injectTerminalInput,
            object: nil,
            userInfo: ["input": prompt]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted to inject input into the terminal
    static let injectTerminalInput = Notification.Name("com.claudecodexcode.injectTerminalInput")
}

// MARK: - Terminal Container

/// Container that manages terminal and theme updates without recreating the terminal
struct TerminalContainerView: View {
    var workingDirectory: URL?
    var theme: Theme
    var onProcessTerminated: ((Int32?) -> Void)?

    @State private var terminalRef: AnyObject?

    var body: some View {
        ClaudeTerminalView(
            workingDirectory: workingDirectory,
            theme: theme,
            terminalRef: $terminalRef,
            onProcessTerminated: onProcessTerminated
        )
        .onChange(of: theme.name) { oldValue, newValue in
            print("[TerminalContainer] Theme changed from '\(oldValue)' to '\(newValue)'")
            // Apply theme directly to terminal if we have a reference
            if let terminal = terminalRef as? SwiftTerm.LocalProcessTerminalView {
                print("[TerminalContainer] Applying theme directly to terminal")
                applyThemeToTerminal(theme, terminal: terminal)
            }
        }
        // Handle terminal input injection
        .onReceive(NotificationCenter.default.publisher(for: .injectTerminalInput)) { notification in
            if let input = notification.userInfo?["input"] as? String,
               let terminal = terminalRef as? SwiftTerm.LocalProcessTerminalView {
                injectInput(input, into: terminal)
            }
        }
    }

    private func applyThemeToTerminal(_ theme: Theme, terminal: SwiftTerm.LocalProcessTerminalView) {
        terminal.nativeBackgroundColor = theme.backgroundColor
        terminal.nativeForegroundColor = theme.foregroundColor
        terminal.caretColor = theme.cursorColor
        terminal.selectedTextBackgroundColor = theme.selectionColor
        terminal.font = theme.font

        // Apply ANSI colors
        let swiftTermColors = theme.ansiColors.map { nsColor -> SwiftTerm.Color in
            let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
            let red = UInt16(color.redComponent * 65535)
            let green = UInt16(color.greenComponent * 65535)
            let blue = UInt16(color.blueComponent * 65535)
            return SwiftTerm.Color(red: red, green: green, blue: blue)
        }
        terminal.installColors(swiftTermColors)
        terminal.needsDisplay = true
    }

    /// Inject text input into the terminal
    private func injectInput(_ text: String, into terminal: SwiftTerm.LocalProcessTerminalView) {
        // Send the text followed by newline
        let inputWithNewline = text + "\n"
        let bytes = Array(inputWithNewline.utf8)
        terminal.send(data: bytes[...])

        // Make sure terminal has focus
        terminal.window?.makeFirstResponder(terminal)
    }
}

// MARK: - Visual Effect Blur

/// Visual effect blur background
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Preview

#Preview {
    MainContentView()
        .frame(width: 420, height: 600)
}
