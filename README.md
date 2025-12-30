# ClaudeCodeXCode

A native macOS companion for Xcode that brings Claude Code's terminal power into a floating panel—with an experimental "Whisper" system that lets AI pair-program without breaking your flow.

[Apply Fix](https://github.com/user-attachments/assets/a10edbd7-a236-4c21-ae81-33cc1747a983)

## The Problem

Xcode has no built-in AI assistance. Switching to a terminal breaks context. Copy-pasting code is friction. And constant AI interruptions are worse than no AI at all.

## The Approach

**What if an AI assistant could watch you code and only speak up when it had something genuinely useful to say?**

ClaudeCodeXCode explores this through:

1. **A floating panel** that embeds the full Claude Code CLI, themed to match Xcode
2. **"Whispers"** — brief, non-intrusive suggestions triggered on file save (⌘S)
3. **One-key actions** — F1 to apply, F2 to expand, F3 to dismiss (no mouse required)

The interaction model prioritizes developer agency: suggestions appear *after* you've made a decision (saved), not while you're thinking. You stay in control of when to receive input.

---

## Design Decisions

### Why a Floating Panel?

Xcode's extension model is extremely limited. A floating `NSPanel` lets us:
- Maintain full CLI functionality (no sandboxing restrictions)
- Position anywhere on screen without competing for Xcode's layout
- Use global hotkeys that work even when Xcode is focused

### Why Trigger on File Save?

Early prototypes used continuous polling—every keystroke could spawn a suggestion. This was exhausting. The insight: **a save is an intentional checkpoint**. The developer has made a micro-decision. That's the right moment to offer input.

### Why Whispers?

"Whisper" captures the tone: a colleague glancing at your screen and murmuring "hey, that variable name is a bit cryptic" rather than interrupting with a formal code review. The model (Claude Haiku 4.5) is tuned for brevity—1-2 sentences max.

When there's nothing to say, the UI briefly shows "All looks good" and fades. No badge. No notification. Just acknowledgment.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Context Bar          File1.swift → File2.swift              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                    Claude Code CLI                           │
│                    (SwiftTerm PTY)                           │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  💭 "processData is generic—maybe parseUserResponse?"        │
│     [F1 Apply]    [F2 Tell me more]    [F3 Dismiss]          │
└──────────────────────────────────────────────────────────────┘
```

### Integration Stack

| Layer | Technique | Why |
|-------|-----------|-----|
| Current file detection | AppleScript polling | Only way to query Xcode's active document |
| File change detection | FSEvents | Native, efficient filesystem watching |
| Live buffer reading | Accessibility API | Get unsaved content from Xcode's editor |
| Theme sync | Parse `.xccolortheme` plist | Match Xcode's exact colors/fonts |
| Patch application | Accessibility API | Modify Xcode's editor buffer directly via AXUIElement |
| Panel behavior | NSPanel + window level tricks | Float above Xcode but behind other apps |

### The Whisper Pipeline

```
File Save (⌘S)
    ↓
XcodeWatcher detects change via FSEvents
    ↓
AppleScript fetches current file + live buffer content
    ↓
Diff computed against previous state
    ↓
Context (diff + full file) sent to Haiku 4.5
    ↓
WhisperService displays result with animations
    ↓
User responds: F1 (apply) | F2 (expand into terminal) | F3 (dismiss)
```

---

## Implementation Notes

### Terminal Emulation

SwiftTerm provides full PTY support—ANSI colors, Unicode, mouse events, 256-color mode. The terminal runs Claude Code directly, inheriting the user's shell environment and PATH.

### Window Management

The panel tracks Xcode's visibility state:
- When Xcode is frontmost → panel floats above
- When another app is frontmost → panel goes behind
- When Xcode minimizes → panel follows with genie animation

This required observing `NSWorkspace` notifications and dynamically adjusting `NSWindow.Level`.

### Patch Application

Applying whisper suggestions uses macOS Accessibility APIs to modify Xcode's editor buffer directly. The patcher finds the focused text area via `AXUIElement`, locates the target code, sets a selection range, and replaces the selected text—all without touching the filesystem. This avoids the reload flicker that file writes would cause. Falls back to disk writes if Accessibility permissions aren't available.

### Animation System

Each whisper action has a distinct animation:
- **Apply**: Spinner → checkmark (or X on failure) → fade
- **Tell me more**: "Genie" effect—pinch horizontally, stretch vertically, accelerate upward into terminal
- **Dismiss**: Scale-down poof

These communicate state without requiring text or dialogs.

#### F1 — Apply Fix
https://github.com/user-attachments/assets/placeholder-apply-video

#### F2 — Tell Me More
https://github.com/user-attachments/assets/placeholder-expand-video

#### Casual Observation (no patch)
https://github.com/user-attachments/assets/placeholder-observation-video

> Replace placeholders by uploading `media/*.mp4` files to a GitHub issue.

---

## Open Questions

This is an exploration, not a finished product. Some things I'm still thinking about:

- **Latency bottleneck**: The biggest delay isn't the model—it's Xcode's save-to-disk cycle before we can detect the change. A true Xcode Source Editor Extension could hook directly into buffer changes, eliminating this entirely. Worth the sandboxing tradeoffs?
- **Suggestion quality vs. latency**: Haiku is fast but sometimes shallow. Sonnet is deeper but adds noticeable delay. Is there a hybrid approach?
- **Context window management**: Currently sends 200 lines + recent diff. For large files, what's the right truncation strategy?
- **Multi-file awareness**: Whispers only see the current file. How could cross-file context work without overwhelming the model?
- **Undo integration**: Patches work, but there's no native undo. Should the app maintain its own undo stack?

---

## Running It

```bash
swift build
.build/debug/ClaudeCodeXCode
```

Requires:
- macOS 14+
- Xcode installed (for integration)
- Claude Code CLI in PATH
- Anthropic API key (stored in Keychain via Settings)

---

## Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulation |
| [HotKey](https://github.com/soffes/HotKey) | Global keyboard shortcuts |

---

## Why I Built This

I use Claude Code daily—full terminal, full control. But some colleagues find that mode too much like *delegation*. They want a partner, not an agent they hand tasks off to. They want to stay in their editor, stay in flow, and have AI chime in when it notices something.

This tool is for them. It's an experiment in a different interaction model: AI as ambient pair programmer rather than autonomous agent. The Whisper concept captures this—brief observations from a colleague glancing at your screen, not a code review you requested.

The patterns here—intentional triggers, non-blocking UI, keyboard-first actions, state-communicating animations—feel transferable to other contexts where humans and AI work alongside each other rather than in handoff mode.
