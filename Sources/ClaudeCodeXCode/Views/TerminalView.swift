import SwiftUI
import SwiftTerm

/// SwiftTerm-based terminal view for full Claude Code experience
/// Uses LocalProcessTerminalView for built-in PTY handling
struct ClaudeTerminalView: NSViewRepresentable {
    /// Working directory for the Claude process
    var workingDirectory: URL?

    /// Theme to apply to the terminal
    var theme: Theme = .xcodeDefaultDark

    /// Binding to store reference to the terminal for direct updates
    @Binding var terminalRef: AnyObject?

    /// Callback when process terminates
    var onProcessTerminated: ((Int32?) -> Void)?

    /// Callback when terminal title changes
    var onTitleChanged: ((String) -> Void)?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)

        // Configure autoresizing to fill container
        terminal.translatesAutoresizingMaskIntoConstraints = true
        terminal.autoresizingMask = [.width, .height]

        // Apply theme colors and font
        applyTheme(theme, to: terminal)

        // Set delegate for process lifecycle
        terminal.processDelegate = context.coordinator

        // Start Claude Code process
        startClaudeProcess(in: terminal)

        // Store reference for direct theme updates
        DispatchQueue.main.async {
            self.terminalRef = terminal
            terminal.window?.makeFirstResponder(terminal)
        }

        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        // Check if theme changed and reapply
        let currentThemeName = context.coordinator.currentTheme?.name ?? "nil"
        let newThemeName = theme.name

        if context.coordinator.currentTheme?.name != theme.name {
            print("[TerminalView] Theme changed from '\(currentThemeName)' to '\(newThemeName)' - applying")
            applyTheme(theme, to: terminal)
            context.coordinator.currentTheme = theme
        }

        // Ensure terminal stays as first responder for keyboard input
        if terminal.window?.firstResponder != terminal {
            terminal.window?.makeFirstResponder(terminal)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTerminated: onProcessTerminated,
            onTitleChanged: onTitleChanged
        )
    }

    /// Apply theme colors and font to the terminal
    private func applyTheme(_ theme: Theme, to terminal: LocalProcessTerminalView) {
        // Apply main colors
        terminal.nativeBackgroundColor = theme.backgroundColor
        terminal.nativeForegroundColor = theme.foregroundColor
        terminal.caretColor = theme.cursorColor
        terminal.selectedTextBackgroundColor = theme.selectionColor

        // Apply font
        terminal.font = theme.font

        // Apply ANSI color palette
        // Convert NSColor array to SwiftTerm Color array
        let swiftTermColors = theme.ansiColors.map { nsColor -> SwiftTerm.Color in
            // Convert NSColor to sRGB color space for consistent values
            let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
            // SwiftTerm Color uses UInt16 for RGB (0-65535 range)
            let red = UInt16(color.redComponent * 65535)
            let green = UInt16(color.greenComponent * 65535)
            let blue = UInt16(color.blueComponent * 65535)
            return SwiftTerm.Color(red: red, green: green, blue: blue)
        }
        terminal.installColors(swiftTermColors)

        // Force redraw
        terminal.needsDisplay = true
    }

    /// Start the Claude Code process in the terminal
    private func startClaudeProcess(in terminal: LocalProcessTerminalView) {
        let claudePath = ClaudeCodeService.findClaudePath()

        // Get proper shell environment with PATH
        var environment = Self.getShellEnvironment()

        // Ensure proper terminal settings
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"

        // Set HOME if not present
        if environment["HOME"] == nil {
            environment["HOME"] = NSHomeDirectory()
        }

        // Set working directory in environment
        let workDir = workingDirectory?.path ?? NSHomeDirectory()
        environment["PWD"] = workDir

        // Convert environment to [String] format for SwiftTerm
        let envArray = environment.map { "\($0.key)=\($0.value)" }

        // Change to working directory before starting claude
        // We use a shell wrapper to ensure we're in the right directory
        let shell = environment["SHELL"] ?? "/bin/zsh"

        terminal.startProcess(
            executable: shell,
            args: ["-c", "cd \"\(workDir)\" && exec \"\(claudePath)\""],
            environment: envArray,
            execName: "claude"
        )
    }

    /// Get environment from user's shell to include proper PATH
    private static func getShellEnvironment() -> [String: String] {
        // Start with current process environment
        var env = ProcessInfo.processInfo.environment

        // Get the user's shell
        let shell = env["SHELL"] ?? "/bin/zsh"

        // Common paths that might be missing from GUI apps
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin",  // nvm
            "\(NSHomeDirectory())/.npm-global/bin",
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        // Try to get PATH from shell
        if let shellPath = getPathFromShell(shell: shell) {
            env["PATH"] = shellPath
        } else {
            // Fallback: extend existing PATH with common locations
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            let expandedPaths = additionalPaths.flatMap { path -> [String] in
                if path.contains("*") {
                    // Expand glob patterns
                    return expandGlob(path)
                }
                return [path]
            }
            let newPath = (expandedPaths + [currentPath]).joined(separator: ":")
            env["PATH"] = newPath
        }

        return env
    }

    /// Get PATH by running the user's shell
    private static func getPathFromShell(shell: String) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: shell)
        // Use login shell to source profile files
        process.arguments = ["-l", "-c", "echo $PATH"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Set minimal environment for the shell
        process.environment = [
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "SHELL": shell
        ]

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {
            print("Failed to get PATH from shell: \(error)")
        }

        return nil
    }

    /// Expand glob patterns in paths
    private static func expandGlob(_ pattern: String) -> [String] {
        let fm = FileManager.default

        // Handle simple * glob in path
        let components = pattern.components(separatedBy: "*")
        guard components.count == 2 else { return [] }

        let baseDir = components[0]
        let suffix = components[1]

        guard let contents = try? fm.contentsOfDirectory(atPath: baseDir) else {
            return []
        }

        return contents.compactMap { item in
            let fullPath = baseDir + item + suffix
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir) {
                return fullPath
            }
            return nil
        }
    }

    /// Coordinator to handle LocalProcessTerminalViewDelegate callbacks
    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onTerminated: ((Int32?) -> Void)?
        var onTitleChanged: ((String) -> Void)?
        var currentTheme: Theme?

        init(onTerminated: ((Int32?) -> Void)?, onTitleChanged: ((String) -> Void)?) {
            self.onTerminated = onTerminated
            self.onTitleChanged = onTitleChanged
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal size changed - handled internally by SwiftTerm
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            DispatchQueue.main.async { [weak self] in
                self?.onTitleChanged?(title)
            }
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // Working directory changed - could update UI if needed
        }

        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                self?.onTerminated?(exitCode)
            }
        }
    }
}

// MARK: - Protocol for future abstraction

/// Protocol for terminal providers - allows swapping implementations
protocol TerminalProvider {
    func createTerminal() -> NSView
    func startProcess(path: String, args: [String], environment: [String: String])
    func sendInput(_ text: String)
    func terminate()
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State var terminalRef: AnyObject?
        var body: some View {
            ClaudeTerminalView(terminalRef: $terminalRef)
                .frame(width: 600, height: 400)
        }
    }
    return PreviewWrapper()
}
