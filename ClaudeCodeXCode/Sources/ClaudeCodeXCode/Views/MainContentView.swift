import SwiftUI

/// Main content view with split layout: Chat on top, Terminal on bottom
struct MainContentView: View {
    @StateObject private var claudeService = ClaudeCodeService()
    @State private var inputText: String = ""
    @State private var splitRatio: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            // Title bar area
            TitleBarView()

            // Split view: Chat + Terminal
            GeometryReader { geometry in
                VSplitView {
                    // Top: Chat interface
                    ChatPanelView(
                        messages: claudeService.messages,
                        inputText: $inputText,
                        onSend: sendMessage
                    )
                    .frame(minHeight: 150)

                    // Bottom: Terminal output
                    TerminalPanelView(output: claudeService.rawOutput)
                        .frame(minHeight: 100)
                }
            }
        }
        .background(VisualEffectBlur())
        .preferredColorScheme(.dark)
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        claudeService.send(inputText)
        inputText = ""
    }
}

/// Title bar with app name and controls
struct TitleBarView: View {
    var body: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .foregroundColor(.orange)

            Text("Claude Code")
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Button(action: {}) {
                Image(systemName: "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }
}

/// Chat panel with messages and input
struct ChatPanelView: View {
    let messages: [ChatMessage]
    @Binding var inputText: String
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input field
            HStack(spacing: 12) {
                TextField("Ask Claude Code...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit(onSend)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.isEmpty ? .gray : .orange)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
            .padding(12)
            .background(Color.black.opacity(0.1))
        }
    }
}

/// Individual message bubble
struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Claude")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(message.content)
                    .padding(12)
                    .background(message.isUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .textSelection(.enabled)
            }

            if !message.isUser {
                Spacer()
            }
        }
    }
}

/// Terminal output panel
struct TerminalPanelView: View {
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Terminal header
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                Text("Terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))

            // Terminal content
            ScrollView {
                Text(output.isEmpty ? "Claude Code output will appear here..." : output)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(output.isEmpty ? .gray : .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Color.black.opacity(0.5))
        }
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
