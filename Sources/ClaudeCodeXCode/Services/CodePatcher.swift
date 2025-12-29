import Foundation

/// Service for applying code patches from whispers
enum CodePatcher {
    /// Result of applying a patch
    enum PatchResult {
        case success
        case fileNotFound
        case codeNotFound
        case writeError(Error)
    }

    /// Apply a whisper patch to the file
    static func apply(_ patch: WhisperPatch) -> PatchResult {
        let filePath = patch.filePath

        // Read file
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("[CodePatcher] File not found: \(filePath)")
            return .fileNotFound
        }

        // Check if old code exists
        guard content.contains(patch.oldCode) else {
            print("[CodePatcher] Code not found in file: \(patch.oldCode.prefix(50))...")
            return .codeNotFound
        }

        // Apply patch
        let newContent = content.replacingOccurrences(of: patch.oldCode, with: patch.newCode)

        // Write file
        do {
            try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            print("[CodePatcher] Successfully patched: \(filePath)")
            return .success
        } catch {
            print("[CodePatcher] Write error: \(error)")
            return .writeError(error)
        }
    }

    /// Preview a patch (returns the result without applying)
    static func preview(_ patch: WhisperPatch) -> (canApply: Bool, context: String?) {
        guard let content = try? String(contentsOfFile: patch.filePath, encoding: .utf8) else {
            return (false, nil)
        }

        guard let range = content.range(of: patch.oldCode) else {
            return (false, nil)
        }

        // Get some context around the change
        let startIndex = content.index(range.lowerBound, offsetBy: -50, limitedBy: content.startIndex) ?? content.startIndex
        let endIndex = content.index(range.upperBound, offsetBy: 50, limitedBy: content.endIndex) ?? content.endIndex

        let context = String(content[startIndex..<endIndex])
        return (true, context)
    }

    /// Validate that a patch can be applied
    static func canApply(_ patch: WhisperPatch) -> Bool {
        guard let content = try? String(contentsOfFile: patch.filePath, encoding: .utf8) else {
            return false
        }
        return content.contains(patch.oldCode)
    }
}
