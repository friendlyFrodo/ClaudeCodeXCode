import SwiftUI

/// Displays a whisper from Claude with action buttons
/// The whisper appears at the bottom of the panel
struct WhisperBubble: View {
    let whisper: Whisper
    let onApply: () -> Void
    let onExpand: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Message row
            HStack(alignment: .top, spacing: 8) {
                Text("💭")
                    .font(.system(size: 16))

                Text(whisper.message)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                // Dismiss button (always visible)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.5)
            }

            // Action buttons
            HStack(spacing: 12) {
                if whisper.canApply {
                    WhisperActionButton(
                        label: "Apply",
                        shortcut: "F1",
                        isPrimary: true,
                        action: onApply
                    )
                }

                WhisperActionButton(
                    label: "Tell me more",
                    shortcut: "F2",
                    isPrimary: !whisper.canApply,
                    action: onExpand
                )

                WhisperActionButton(
                    label: "Dismiss",
                    shortcut: "F3",
                    isPrimary: false,
                    action: onDismiss
                )

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

/// A single action button with keyboard shortcut display
struct WhisperActionButton: View {
    let label: String
    let shortcut: String
    let isPrimary: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isPrimary ? .accentColor : .secondary)

                Text(label)
                    .font(.system(size: 11, weight: isPrimary ? .medium : .regular))
                    .foregroundColor(isPrimary ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundColor: Color {
        if isHovering {
            return isPrimary ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15)
        }
        return isPrimary ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08)
    }
}

// MARK: - Container for Animation

/// Container view that handles whisper appearance/disappearance animation
struct WhisperContainer: View {
    let whisper: Whisper?
    let onApply: () -> Void
    let onExpand: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            if let whisper = whisper {
                WhisperBubble(
                    whisper: whisper,
                    onApply: onApply,
                    onExpand: onExpand,
                    onDismiss: onDismiss
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: whisper?.id)
    }
}

// MARK: - Preview

#Preview("With Patch") {
    VStack {
        Spacer()
        WhisperBubble(
            whisper: Whisper(
                message: "Hmm, `cnt` is a bit cryptic - maybe `userCount`?",
                canApply: true,
                patch: WhisperPatch(
                    filePath: "/path/to/file.swift",
                    oldCode: "var cnt = 0",
                    newCode: "var userCount = 0"
                )
            ),
            onApply: { print("Apply") },
            onExpand: { print("Expand") },
            onDismiss: { print("Dismiss") }
        )
        .padding()
    }
    .frame(width: 450, height: 200)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Observation Only") {
    VStack {
        Spacer()
        WhisperBubble(
            whisper: Whisper(
                message: "That's a clean guard clause 👌",
                canApply: false,
                patch: nil
            ),
            onApply: { },
            onExpand: { print("Expand") },
            onDismiss: { print("Dismiss") }
        )
        .padding()
    }
    .frame(width: 450, height: 200)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Long Message") {
    VStack {
        Spacer()
        WhisperBubble(
            whisper: Whisper(
                message: "This function is getting quite long - might be worth splitting the validation logic into a separate method for clarity and testability.",
                canApply: false,
                patch: nil
            ),
            onApply: { },
            onExpand: { print("Expand") },
            onDismiss: { print("Dismiss") }
        )
        .padding()
    }
    .frame(width: 450, height: 200)
    .background(Color(NSColor.windowBackgroundColor))
}
