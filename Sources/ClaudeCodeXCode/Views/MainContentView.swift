import SwiftUI
import SwiftTerm

/// Main content view with full terminal interface
struct MainContentView: View {
    @StateObject private var claudeService = ClaudeCodeService()
    @StateObject private var themeReader = XcodeThemeReader()

    var body: some View {
        // Full terminal view filling entire window
        TerminalContainerView(
            workingDirectory: claudeService.workingDirectory,
            theme: themeReader.currentTheme,
            onProcessTerminated: { exitCode in
                claudeService.handleProcessTerminated(exitCode: exitCode)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            claudeService.handleProcessStarted()
        }
        .background(VisualEffectBlur())
        .preferredColorScheme(themeReader.currentTheme.isDark ? .dark : .light)
    }
}

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
}

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

#Preview {
    MainContentView()
        .frame(width: 420, height: 600)
}
