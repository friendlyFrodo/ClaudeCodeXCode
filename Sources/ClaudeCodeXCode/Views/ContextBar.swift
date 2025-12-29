import SwiftUI

/// Displays the current context - files Claude is "watching"
/// Shows the last 3 files touched since the last prompt
struct ContextBar: View {
    @ObservedObject var contextTracker: ContextTracker

    /// Whether to show the processing indicator
    var isProcessing: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // Eye icon indicating "watching"
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // File names
            if contextTracker.trackedFileNames.isEmpty {
                Text("Watching Xcode...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(contextTracker.trackedFileNames.enumerated()), id: \.offset) { index, fileName in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                    }

                    Text(fileName)
                        .font(.system(size: 11, weight: index == 0 ? .medium : .regular))
                        .foregroundColor(index == 0 ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Processing indicator
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        // With files
        ContextBar(
            contextTracker: {
                let tracker = ContextTracker()
                // Simulate some files being tracked
                Task { @MainActor in
                    tracker.setCurrentFile("/path/to/FloatingPanel.swift")
                    tracker.setCurrentFile("/path/to/Theme.swift")
                    tracker.setCurrentFile("/path/to/MainContentView.swift")
                }
                return tracker
            }(),
            isProcessing: false
        )

        Divider()

        // Processing
        ContextBar(
            contextTracker: ContextTracker(),
            isProcessing: true
        )

        Divider()

        // Empty state
        ContextBar(
            contextTracker: ContextTracker(),
            isProcessing: false
        )
    }
    .frame(width: 400)
}
