# Claude Code Instructions for ClaudeCodeXCode

## Project Overview

This is **ClaudeCodeXCode** - a native macOS floating companion app that integrates Claude Code CLI with Xcode. The goal is maximum user-friendliness and beauty while maintaining full Claude Code power.

## Source of Truth

**IMPORTANT**: The file `DESIGN.md` in this repository is the **source of truth** for all design decisions, implementation progress, and technical specifications.

### Before Starting Any Work

1. **Always read `DESIGN.md` first** - It contains:
   - The hardcoded UI/UX design decisions
   - Current implementation progress
   - Project structure
   - Technical notes and code snippets
   - Open questions

2. **Update `DESIGN.md` when**:
   - Completing a task or phase
   - Making design decisions
   - Changing architecture
   - Adding new features
   - Discovering technical constraints

3. **The design in `DESIGN.md` is FINAL** - Do not deviate from the hardcoded design decisions unless explicitly discussed with the user.

## Key Design Decisions (Summary)

- **Window**: Floating NSPanel that stays above other windows
- **Layout**: Split view - Chat on top, Terminal on bottom
- **Theme**: Sync colors/fonts from Xcode's theme files
- **Integration**: Maximum hackery (FSEvents, AppleScript, Accessibility, Clipboard)
- **Hotkey**: ⌘⇧C to toggle visibility

## Repository Structure

```
ClaudeCodeXCode/
├── CLAUDE.md          # This file - Claude instructions
├── DESIGN.md          # Source of truth (GITIGNORED - local only)
├── Package.swift      # Swift Package manifest
├── README.md          # Public readme
└── Sources/           # Swift source code
```

## Build Commands

```bash
# Build
swift build

# Run
.build/debug/ClaudeCodeXCode

# Clean build
swift package clean && swift build
```

## Git Workflow

- Main branch: `main`
- Remote: `https://github.com/friendlyFrodo/ClaudeCodeXCode`
- User: `friendlyFrodo` / `friedrich.wanierke@googlemail.com`

## Current Phase

Check `DESIGN.md` → "Implementation Progress" section for current status.

## Dependencies

- **SwiftTerm** - Terminal emulation
- **HotKey** - Global keyboard shortcuts
- **Sparkle** - Auto-updates (future)

## Notes for New Sessions

When starting a new Claude Code session on this project:

1. Read this file (CLAUDE.md)
2. Read DESIGN.md thoroughly
3. Check git status for any uncommitted changes
4. Review the "Implementation Progress" section
5. Continue from where the last session left off

This ensures continuity across sessions and prevents design drift.
