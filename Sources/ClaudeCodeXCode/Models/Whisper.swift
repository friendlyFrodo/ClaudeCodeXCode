import Foundation

/// Represents a whisper - a brief, casual observation from Claude about the user's code
struct Whisper: Identifiable, Equatable {
    let id: UUID
    let message: String
    let canApply: Bool
    let patch: WhisperPatch?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        message: String,
        canApply: Bool = false,
        patch: WhisperPatch? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.message = message
        self.canApply = canApply
        self.patch = patch
        self.timestamp = timestamp
    }

    static func == (lhs: Whisper, rhs: Whisper) -> Bool {
        lhs.id == rhs.id
    }
}

/// A code patch that can be applied via the "Apply" action
struct WhisperPatch: Equatable {
    let filePath: String
    let oldCode: String
    let newCode: String

    /// Validate that the patch can be applied (old code exists in file)
    func canApply() -> Bool {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return false
        }
        return content.contains(oldCode)
    }
}

// MARK: - JSON Parsing (from Haiku response)

extension Whisper {
    /// Parse a Whisper from Haiku's JSON response
    static func fromHaikuResponse(_ json: [String: Any], currentFile: String?) -> Whisper? {
        // Check if whisper is null (nothing to say)
        guard let message = json["whisper"] as? String else {
            return nil
        }

        let canApply = json["can_apply"] as? Bool ?? false

        var patch: WhisperPatch? = nil
        if let patchData = json["patch"] as? [String: String],
           let oldCode = patchData["old"],
           let newCode = patchData["new"] {

            // Resolve file path: if Haiku returns just a filename, use the full path from context
            var filePath = patchData["file"] ?? currentFile

            // If the returned path is just a filename (no directory separator), use currentFile
            if let path = filePath, !path.contains("/"), let fullPath = currentFile {
                print("[Whisper] Haiku returned relative path '\(path)', using full path: \(fullPath)")
                filePath = fullPath
            } else if let path = filePath {
                print("[Whisper] Using file path from Haiku: \(path)")
            }

            guard let resolvedPath = filePath else {
                print("[Whisper] No valid file path available")
                return Whisper(message: message, canApply: false, patch: nil)
            }

            patch = WhisperPatch(
                filePath: resolvedPath,
                oldCode: oldCode,
                newCode: newCode
            )
        }

        return Whisper(
            message: message,
            canApply: canApply && patch != nil,
            patch: patch
        )
    }
}
