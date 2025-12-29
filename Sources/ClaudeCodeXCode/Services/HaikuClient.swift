import Foundation

/// Client for calling Claude Haiku API for fast whisper generation
actor HaikuClient {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5"
    private let maxTokens = 512

    /// API key loaded from Claude CLI config or environment
    private var apiKey: String?

    init() {
        self.apiKey = Self.loadAPIKey()
    }

    // MARK: - API Key Loading

    /// Load API key from Keychain, environment, or config files
    private static func loadAPIKey() -> String? {
        // 1. Check Keychain (set via Settings UI)
        if let keychainKey = KeychainHelper.loadApiKey(), !keychainKey.isEmpty {
            print("[HaikuClient] Using API key from Keychain")
            return keychainKey
        }

        // 2. Check environment variable
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            print("[HaikuClient] Using API key from ANTHROPIC_API_KEY environment variable")
            return envKey
        }

        // 3. Check Claude CLI config file (~/.claude.json or ~/.config/claude/config.json)
        let homeDir = NSHomeDirectory()
        let configPaths = [
            "\(homeDir)/.claude.json",
            "\(homeDir)/.config/claude/config.json",
            "\(homeDir)/.claude/config.json"
        ]

        for path in configPaths {
            if let key = loadKeyFromConfig(path) {
                print("[HaikuClient] Using API key from: \(path)")
                return key
            }
        }

        // 4. Check for API key file
        let keyFilePaths = [
            "\(homeDir)/.claude/api_key",
            "\(homeDir)/.anthropic/api_key"
        ]

        for path in keyFilePaths {
            if let key = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                print("[HaikuClient] Using API key from: \(path)")
                return key
            }
        }

        print("[HaikuClient] WARNING: No API key found. Set it in Settings (⌘,) or ANTHROPIC_API_KEY env var.")
        return nil
    }

    private static func loadKeyFromConfig(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Try different key names
        let keyNames = ["apiKey", "api_key", "anthropic_api_key", "ANTHROPIC_API_KEY"]
        for keyName in keyNames {
            if let key = json[keyName] as? String, !key.isEmpty {
                return key
            }
        }

        return nil
    }

    // MARK: - Whisper Generation

    /// Request a whisper from Haiku based on the current context
    func getWhisper(context: CodeContext) async throws -> Whisper? {
        print("[HaikuClient] getWhisper called, hasAPIKey: \(apiKey != nil)")

        guard let apiKey = apiKey else {
            print("[HaikuClient] ERROR: No API key!")
            throw HaikuError.noAPIKey
        }

        let prompt = buildPrompt(context: context)
        print("[HaikuClient] Built prompt (\(prompt.count) chars), calling \(model)...")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10  // Fast timeout for responsiveness

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HaikuError.invalidResponse
        }

        print("[HaikuClient] Response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[HaikuClient] API error \(httpResponse.statusCode): \(errorBody)")
            throw HaikuError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let responseStr = String(data: data, encoding: .utf8) ?? ""
        print("[HaikuClient] Response body: \(responseStr.prefix(500))...")

        return try parseResponse(data, currentFile: context.currentFile)
    }

    // MARK: - Prompt Building

    private func buildPrompt(context: CodeContext) -> String {
        var parts: [String] = []

        parts.append("""
        You are a pair programmer watching code in real-time.

        CRITICAL: Respond with ONLY a JSON object. No markdown code blocks. No explanation.

        PRIORITY: If you see "RECENT CHANGES", focus your comment on those specific changes.
        Look for: bugs, typos, missing imports, syntax errors, obvious issues in the changed lines.

        Guidelines:
        - Only whisper if you notice something genuinely useful
        - Max 1-2 sentences, casual tone ("hmm", "maybe", "looks like...")
        - If nothing worth saying, return {"whisper": null, "can_apply": false, "patch": null}

        CONTEXT:
        """)

        if let file = context.currentFileName {
            parts.append("Current file: \(file)")
        }

        if !context.recentFileNames.isEmpty {
            parts.append("Recent files: \(context.recentFileNames.joined(separator: ", "))")
        }

        if let function = context.currentFunction {
            parts.append("Current function: \(function)")
        }

        if let status = context.buildStatus {
            parts.append("Build status: \(status.description)")
        }

        if let change = context.codeChange {
            parts.append("""

            CODE CHANGE:
            ```\(context.language)
            \(change)
            ```
            """)
        }

        parts.append("""

        Respond with JSON only (no markdown, no explanation):
        {
          "whisper": "Your casual observation" | null,
          "can_apply": true | false,
          "patch": {
            "file": "/full/path/to/file.swift",
            "old": "exact original code",
            "new": "suggested replacement"
          } | null
        }
        """)

        return parts.joined(separator: "\n")
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data, currentFile: String?) throws -> Whisper? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw HaikuError.parseError
        }

        // Extract JSON from response (might have markdown code blocks)
        let jsonString = extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8),
              let whisperJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("[HaikuClient] Failed to parse whisper JSON: \(text)")
            return nil
        }

        return Whisper.fromHaikuResponse(whisperJson, currentFile: currentFile)
    }

    /// Extract JSON from response text (handles markdown code blocks)
    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it starts with {, assume it's already JSON
        if trimmed.hasPrefix("{") {
            return trimmed
        }

        // Try to extract from markdown code block
        if let jsonStart = trimmed.range(of: "```json"),
           let jsonEnd = trimmed.range(of: "```", range: jsonStart.upperBound..<trimmed.endIndex) {
            return String(trimmed[jsonStart.upperBound..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to extract from generic code block
        if let jsonStart = trimmed.range(of: "```"),
           let jsonEnd = trimmed.range(of: "```", range: jsonStart.upperBound..<trimmed.endIndex) {
            return String(trimmed[jsonStart.upperBound..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON object in text
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }

    // MARK: - API Key Management

    /// Check if API key is available
    var hasAPIKey: Bool {
        apiKey != nil
    }

    /// Reload API key (e.g., after user configures it)
    func reloadAPIKey() {
        apiKey = Self.loadAPIKey()
    }
}

// MARK: - Errors

enum HaikuError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key found. Set ANTHROPIC_API_KEY or configure Claude CLI."
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .parseError:
            return "Failed to parse API response"
        }
    }
}
