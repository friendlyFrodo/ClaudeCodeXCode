import Foundation
import Combine

/// Service for managing Claude Code CLI process
@MainActor
class ClaudeCodeService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var rawOutput: String = ""
    @Published var isRunning: Bool = false

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    init() {
        // Add welcome message
        messages.append(ChatMessage(
            content: "Welcome to Claude Code for Xcode! Type a message to get started.",
            isUser: false
        ))
    }

    /// Send a command to Claude Code
    func send(_ command: String) {
        // Add user message to chat
        messages.append(ChatMessage(content: command, isUser: true))

        // Append to raw output
        rawOutput += "\n> \(command)\n"

        // Start or send to process
        if process == nil || !isRunning {
            startProcess(with: command)
        } else {
            writeToProcess(command)
        }
    }

    /// Start the Claude Code process
    private func startProcess(with initialCommand: String? = nil) {
        process = Process()
        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()

        guard let process = process,
              let inputPipe = inputPipe,
              let outputPipe = outputPipe,
              let errorPipe = errorPipe else { return }

        // Find claude executable
        let claudePath = findClaudePath()

        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = []
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set working directory to user's home or current project
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Handle output
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.handleOutput(output)
                }
            }
        }

        // Handle errors
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.handleError(output)
                }
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isRunning = false
                self?.rawOutput += "\n[Process terminated]\n"
            }
        }

        do {
            try process.run()
            isRunning = true
            rawOutput += "[Claude Code started]\n"

            // Send initial command if provided
            if let command = initialCommand {
                // Small delay to let process initialize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.writeToProcess(command)
                }
            }
        } catch {
            handleError("Failed to start Claude Code: \(error.localizedDescription)")
            messages.append(ChatMessage(
                content: "Error: Could not start Claude Code. Make sure it's installed (`npm install -g @anthropic-ai/claude-code`).",
                isUser: false
            ))
        }
    }

    /// Write input to the running process
    private func writeToProcess(_ text: String) {
        guard let inputPipe = inputPipe else { return }

        let input = text + "\n"
        if let data = input.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
    }

    /// Handle output from the process
    private func handleOutput(_ output: String) {
        rawOutput += output

        // Parse output and add to messages if it looks like a response
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.hasPrefix(">") {
            // Simple heuristic: if output is substantial, add as AI message
            if trimmed.count > 10 {
                messages.append(ChatMessage(content: trimmed, isUser: false))
            }
        }
    }

    /// Handle error output
    private func handleError(_ error: String) {
        rawOutput += "[ERROR] \(error)"
    }

    /// Find the claude executable path
    private func findClaudePath() -> String {
        // Check common locations
        let possiblePaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "\(NSHomeDirectory())/node_modules/.bin/claude"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try using `which` to find it
        let whichProcess = Process()
        let pipe = Pipe()

        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["claude"]
        whichProcess.standardOutput = pipe

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {
            // Fall through to default
        }

        // Default fallback
        return "/usr/local/bin/claude"
    }

    /// Stop the running process
    func stop() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        isRunning = false
    }
}
