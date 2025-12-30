import SwiftUI
import SwiftTerm

/// Main content view with full terminal interface and AI pair programmer features
struct MainContentView: View {
    @StateObject private var claudeService = ClaudeCodeService()
    @StateObject private var themeReader = XcodeThemeReader()
    @StateObject private var whisperService = WhisperService()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content layer
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
                    .frame(
                        width: geometry.size.width,
                        height: calculateTerminalHeight(totalHeight: geometry.size.height)
                    )

                    // Spacer to reserve whisper area
                    Color.clear
                        .frame(height: 200)
                }

                // Whisper layer (on top, can animate over terminal)
                WhisperContainer(
                    whisper: whisperService.currentWhisper,
                    showAllGood: whisperService.showAllGood,
                    onApply: { whisperService.applyWhisper() },  // Returns Bool
                    onExpand: { whisperService.expandWhisper() },
                    onDismiss: { whisperService.dismissWhisper() }
                )
                .frame(height: 200, alignment: .top)
            }
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

    /// Calculate terminal height based on available space
    /// Always reserves space for whisper to prevent layout shifts
    private func calculateTerminalHeight(totalHeight: CGFloat) -> CGFloat {
        let contextBarHeight: CGFloat = 28
        let dividerHeight: CGFloat = 1
        let whisperHeight: CGFloat = 200  // Always reserve space

        let terminalHeight = totalHeight - contextBarHeight - dividerHeight - whisperHeight
        return max(terminalHeight, 200) // Minimum 200px for terminal
    }

    /// Handle the "Tell me more" action by injecting a prompt into the terminal
    private func handleExpandWhisper(_ notification: Notification) {
        guard let message = notification.userInfo?["message"] as? String else { return }

        // The message already contains the full prompt with context from WhisperService
        // Post notification for terminal to handle (terminal will auto-submit with newline)
        NotificationCenter.default.post(
            name: .injectTerminalInput,
            object: nil,
            userInfo: ["input": message]
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

    /// Inject text input into the terminal and submit it
    private func injectInput(_ text: String, into terminal: SwiftTerm.LocalProcessTerminalView) {
        print("[TerminalContainer] Injecting input (\(text.count) chars)")
        print("[TerminalContainer] Preview: \(text.prefix(100))...")

        // Make sure terminal has focus
        terminal.window?.makeFirstResponder(terminal)

        // Send the text first
        let textBytes = Array(text.utf8)
        terminal.send(data: textBytes[...])
        print("[TerminalContainer] Sent \(textBytes.count) bytes of text")

        // Small delay to let Claude Code's TUI process the text input
        // Then send Enter (carriage return = 13) separately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Send CR (Enter key) - same as EscapeSequences.cmdRet in SwiftTerm
            terminal.send([13])
            print("[TerminalContainer] Sent CR (Enter)")
        }
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
