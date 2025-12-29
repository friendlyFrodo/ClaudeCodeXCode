import Foundation
import AppKit
import ApplicationServices

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
        if let axResult = applyInXcodeBuffer(patch) {
            switch axResult {
            case .success:
                print("[CodePatcher] Patched Xcode buffer via Accessibility")
                return .success
            case .codeNotFound:
                print("[CodePatcher] Code not found in Xcode buffer")
                return .codeNotFound
            case .unavailable(let reason):
                print("[CodePatcher] Xcode buffer patch unavailable: \(reason)")
            }
        }
        
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

// MARK: - Xcode Buffer Patching (Accessibility)

private extension CodePatcher {
    enum AXPatchResult {
        case success
        case codeNotFound
        case unavailable(String)
    }

    static func applyInXcodeBuffer(_ patch: WhisperPatch) -> AXPatchResult? {
        guard let xcodeApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dt.Xcode" }) else {
            return .unavailable("Xcode not running")
        }

        let appElement = AXUIElementCreateApplication(xcodeApp.processIdentifier)
        guard let editor = findFocusedEditor(in: appElement) else {
            return .unavailable("Focused editor not found")
        }

        guard let fullText = getTextValue(from: editor) else {
            return .unavailable("Failed to read editor text (Accessibility permission?)")
        }

        let resolved = resolvePatch(oldCode: patch.oldCode, newCode: patch.newCode, in: fullText)
        guard let (oldCode, newCode) = resolved else {
            return .codeNotFound
        }

        let nsText = fullText as NSString
        let matchRange = nsText.range(of: oldCode)
        guard matchRange.location != NSNotFound else {
            return .codeNotFound
        }

        let selectionState = captureSelectionState(from: editor)

        guard setSelectedRange(matchRange, on: editor) else {
            return .unavailable("Failed to set selection range")
        }

        guard setSelectedText(newCode, on: editor) else {
            return .unavailable("Failed to set selected text")
        }

        restoreSelectionState(selectionState, on: editor)
        return .success
    }

    static func findFocusedEditor(in appElement: AXUIElement) -> AXUIElement? {
        if let focused = copyAXElement(appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           isTextElement(focused) {
            return focused
        }

        if let window = copyAXElement(appElement, attribute: kAXFocusedWindowAttribute as CFString) {
            if let direct = findFirstTextElement(in: window, maxDepth: 6) {
                return direct
            }
            return findLargestTextElement(in: window, maxDepth: 6)
        }

        return nil
    }

    static func copyAXElement(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let axValue = value else { return nil }
        return (axValue as! AXUIElement)
    }

    static func isTextElement(_ element: AXUIElement) -> Bool {
        guard let role = copyAXString(element, attribute: kAXRoleAttribute as CFString) else {
            return false
        }
        return role == (kAXTextAreaRole as String)
            || role == (kAXTextFieldRole as String)
    }

    static func findFirstTextElement(in root: AXUIElement, maxDepth: Int) -> AXUIElement? {
        if maxDepth == 0 { return nil }
        if isTextElement(root) { return root }

        guard let children = copyAXArray(root, attribute: kAXChildrenAttribute as CFString) else { return nil }
        for child in children {
            if let found = findFirstTextElement(in: child, maxDepth: maxDepth - 1) {
                return found
            }
        }
        return nil
    }

    static func findLargestTextElement(in root: AXUIElement, maxDepth: Int) -> AXUIElement? {
        if maxDepth == 0 { return nil }
        var best: (AXUIElement, Int)?
        if let text = getTextValue(from: root) {
            best = (root, text.count)
        }
        if let children = copyAXArray(root, attribute: kAXChildrenAttribute as CFString) {
            for child in children {
                if let candidate = findLargestTextElement(in: child, maxDepth: maxDepth - 1) {
                    let size = getTextValue(from: candidate)?.count ?? 0
                    if best == nil || size > (best?.1 ?? 0) {
                        best = (candidate, size)
                    }
                }
            }
        }
        return best?.0
    }

    static func copyAXArray(_ element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let axValue = value as? [AXUIElement] else { return nil }
        return axValue
    }

    static func copyAXString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let str = value as? String else { return nil }
        return str
    }

    static func getTextValue(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let text = value as? String else { return nil }
        return text
    }

    static func setSelectedRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success
    }

    static func setSelectedText(_ text: String, on element: AXUIElement) -> Bool {
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    struct SelectionState {
        let selectedRange: NSRange?
        let visibleRange: NSRange?
    }

    static func captureSelectionState(from element: AXUIElement) -> SelectionState {
        let selected = copyAXRange(element, attribute: kAXSelectedTextRangeAttribute as CFString)
        let visible = copyAXRange(element, attribute: kAXVisibleCharacterRangeAttribute as CFString)
        return SelectionState(selectedRange: selected, visibleRange: visible)
    }

    static func restoreSelectionState(_ state: SelectionState, on element: AXUIElement) {
        if let visible = state.visibleRange {
            _ = AXUIElementSetAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, axRangeValue(visible))
        }
        if let selected = state.selectedRange {
            _ = setSelectedRange(selected, on: element)
        }
    }

    static func copyAXRange(_ element: AXUIElement, attribute: CFString) -> NSRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let rawValue = value else { return nil }
        let axValue = rawValue as! AXValue
        var cfRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &cfRange) else { return nil }
        return NSRange(location: cfRange.location, length: cfRange.length)
    }

    static func axRangeValue(_ range: NSRange) -> AXValue {
        var cfRange = CFRange(location: range.location, length: range.length)
        return AXValueCreate(.cfRange, &cfRange)!
    }

    static func resolvePatch(oldCode: String, newCode: String, in content: String) -> (String, String)? {
        if content.contains(oldCode) {
            return (oldCode, newCode)
        }
        return findWithFlexibleWhitespace(oldCode: oldCode, newCode: newCode, in: content)
    }

    static func findWithFlexibleWhitespace(oldCode: String, newCode: String, in content: String) -> (String, String)? {
        let patchLines = oldCode.components(separatedBy: "\n")
        let newLines = newCode.components(separatedBy: "\n")
        let contentLines = content.components(separatedBy: "\n")

        guard !patchLines.isEmpty, contentLines.count >= patchLines.count else {
            return nil
        }

        let patchTrimmed = patchLines.map { $0.trimmingCharacters(in: .whitespaces) }

        for startIdx in 0...(contentLines.count - patchLines.count) {
            var allMatch = true
            for (offset, patchTrim) in patchTrimmed.enumerated() {
                let contentTrim = contentLines[startIdx + offset].trimmingCharacters(in: .whitespaces)
                if patchTrim != contentTrim {
                    allMatch = false
                    break
                }
            }
            if allMatch {
                let actualLines = Array(contentLines[startIdx..<(startIdx + patchLines.count)])
                let actualOldCode = actualLines.joined(separator: "\n")

                var adjustedNewLines: [String] = []
                for (index, line) in newLines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                    if index < actualLines.count {
                        let indent = actualLines[index].prefix { $0 == " " || $0 == "\t" }
                        adjustedNewLines.append(String(indent) + trimmed)
                    } else {
                        let baseIndent = actualLines.first?.prefix { $0 == " " || $0 == "\t" } ?? ""
                        adjustedNewLines.append(String(baseIndent) + trimmed)
                    }
                }

                let adjustedNewCode = adjustedNewLines.joined(separator: "\n")
                return (actualOldCode, adjustedNewCode)
            }
        }

        return nil
    }
}
