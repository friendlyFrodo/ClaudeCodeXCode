import SwiftUI

/// Main content view with full terminal interface
struct MainContentView: View {
    @StateObject private var claudeService = ClaudeCodeService()

    var body: some View {
        // Full terminal view filling entire window
        ClaudeTerminalView(
            workingDirectory: claudeService.workingDirectory,
            onProcessTerminated: { exitCode in
                claudeService.handleProcessTerminated(exitCode: exitCode)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            claudeService.handleProcessStarted()
        }
        .background(VisualEffectBlur())
        .preferredColorScheme(.dark)
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
