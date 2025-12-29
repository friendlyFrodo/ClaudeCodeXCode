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

// MARK: - Dismissal Animation Types

enum WhisperDismissalType {
    case none
    case apply      // Green checkmark flash + fade
    case expand     // Float up toward terminal
    case dismiss    // Scale-out poof
}

// MARK: - Container for Animation

/// Container view that handles whisper appearance/disappearance animation
struct WhisperContainer: View {
    let whisper: Whisper?
    let onApply: () -> Bool  // Returns true if patch succeeded
    let onExpand: () -> Void
    let onDismiss: () -> Void

    // Animation state
    @State private var dismissalType: WhisperDismissalType = .none
    @State private var showWorking = false  // Spinner while applying
    @State private var showCheckmark = false  // Success indicator
    @State private var showError = false  // Failure indicator
    @State private var animationProgress: CGFloat = 0  // 0 = visible, 1 = gone
    @State private var cachedWhisper: Whisper?  // Keep whisper during animation
    @State private var geniePhase: CGFloat = 0  // For genie effect staging

    var body: some View {
        ZStack(alignment: .top) {
            // Invisible spacer to maintain consistent height
            Color.clear

            if let displayWhisper = cachedWhisper ?? whisper {
                WhisperBubble(
                    whisper: displayWhisper,
                    onApply: { handleApply() },
                    onExpand: { handleExpand() },
                    onDismiss: { handleDismiss() }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .overlay(checkmarkOverlay)
                .opacity(opacityForAnimation)
                .scaleEffect(x: scaleXForAnimation, y: scaleYForAnimation, anchor: .top)
                .offset(y: offsetForAnimation)
            }
        }
        .onChange(of: whisper?.id) { oldValue, newValue in
            // New whisper appeared - reset animation state
            if newValue != nil && oldValue == nil {
                resetState()
            }
        }
    }

    // MARK: - Animation Modifiers

    private var opacityForAnimation: Double {
        switch dismissalType {
        case .apply, .dismiss:
            return 1.0 - animationProgress
        case .expand:
            // Genie: fade out more aggressively at the end
            let easedProgress = animationProgress * animationProgress
            return 1.0 - easedProgress
        case .none:
            return 1.0
        }
    }

    private var scaleXForAnimation: CGFloat {
        switch dismissalType {
        case .dismiss:
            return 1.0 - (animationProgress * 0.7)  // Scale to 0.3
        case .apply:
            return 1.0 - (animationProgress * 0.1)  // Slight shrink
        case .expand:
            // Genie: pinch horizontally more than vertically
            let easedProgress = animationProgress * animationProgress
            return 1.0 - (easedProgress * 0.95)  // Pinch to 5% width
        case .none:
            return 1.0
        }
    }

    private var scaleYForAnimation: CGFloat {
        switch dismissalType {
        case .dismiss:
            return 1.0 - (animationProgress * 0.7)  // Scale to 0.3
        case .apply:
            return 1.0 - (animationProgress * 0.1)  // Slight shrink
        case .expand:
            // Genie: stretch vertically slightly before compressing
            if animationProgress < 0.3 {
                // Initial stretch
                return 1.0 + (animationProgress * 0.15)
            } else {
                // Then compress
                let compressProgress = (animationProgress - 0.3) / 0.7
                return 1.05 - (compressProgress * 0.85)  // From 1.05 to 0.2
            }
        case .none:
            return 1.0
        }
    }

    private var offsetForAnimation: CGFloat {
        switch dismissalType {
        case .expand:
            // Genie: accelerate upward (ease-in curve)
            let easedProgress = animationProgress * animationProgress * animationProgress
            return -easedProgress * 120  // Move up 120pts with acceleration
        default:
            return 0
        }
    }

    // MARK: - Status Overlays (for Apply)

    @ViewBuilder
    private var checkmarkOverlay: some View {
        ZStack {
            // Working spinner
            if showWorking {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.15))

                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            }

            // Success checkmark
            if showCheckmark {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.2))

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
            }

            // Error indicator
            if showError {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.15))

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.red)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Action Handlers

    private func handleApply() {
        guard dismissalType == .none else { return }
        dismissalType = .apply
        cachedWhisper = whisper

        // Show working spinner
        withAnimation(.easeIn(duration: 0.15)) {
            showWorking = true
        }

        // Apply patch after brief delay (let spinner appear)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let success = onApply()

            // Hide spinner, show result
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                showWorking = false
                if success {
                    showCheckmark = true
                } else {
                    showError = true
                }
            }

            // Fade out after showing result
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCheckmark = false
                    showError = false
                    animationProgress = 1.0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    resetState()
                }
            }
        }
    }

    private func handleExpand() {
        guard dismissalType == .none else { return }
        dismissalType = .expand
        cachedWhisper = whisper

        // Genie effect - ease in for acceleration feel
        withAnimation(.easeIn(duration: 0.45)) {
            animationProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onExpand()
            resetState()
        }
    }

    private func handleDismiss() {
        guard dismissalType == .none else { return }
        dismissalType = .dismiss
        cachedWhisper = whisper

        // Poof - scale down and fade
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            animationProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
            resetState()
        }
    }

    private func resetState() {
        dismissalType = .none
        animationProgress = 0
        showWorking = false
        showCheckmark = false
        showError = false
        cachedWhisper = nil
        geniePhase = 0
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
