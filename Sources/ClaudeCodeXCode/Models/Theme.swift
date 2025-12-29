import AppKit

/// Represents a terminal theme with colors and font
/// Can be loaded from Xcode .xccolortheme files or use built-in defaults
struct Theme: Equatable {
    let backgroundColor: NSColor
    let foregroundColor: NSColor
    let cursorColor: NSColor
    let selectionColor: NSColor
    let font: NSFont
    let ansiColors: [NSColor]  // 16 colors: 8 normal + 8 bright
    let name: String
    let isDark: Bool

    // MARK: - Equatable

    static func == (lhs: Theme, rhs: Theme) -> Bool {
        // Compare by name and isDark for efficiency
        // Full color comparison would be expensive
        lhs.name == rhs.name && lhs.isDark == rhs.isDark
    }

    // MARK: - Built-in Fallback Themes

    /// Xcode Default (Dark) theme - used as fallback
    static let xcodeDefaultDark = Theme(
        backgroundColor: NSColor(red: 0.120543, green: 0.122844, blue: 0.141312, alpha: 1.0),
        foregroundColor: NSColor(white: 1.0, alpha: 0.85),
        cursorColor: NSColor(red: 0.0408, green: 0.3748, blue: 0.9984, alpha: 1.0),
        selectionColor: NSColor(red: 0.3176, green: 0.3569, blue: 0.4392, alpha: 1.0),
        font: NSFont(name: "SF Mono", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        ansiColors: defaultDarkAnsiColors,
        name: "Xcode Default (Dark)",
        isDark: true
    )

    /// Xcode Default (Light) theme
    static let xcodeDefaultLight = Theme(
        backgroundColor: NSColor(white: 1.0, alpha: 1.0),
        foregroundColor: NSColor(white: 0.0, alpha: 0.85),
        cursorColor: NSColor(red: 0.0408, green: 0.3748, blue: 0.9984, alpha: 1.0),
        selectionColor: NSColor(red: 0.6431, green: 0.7412, blue: 0.898, alpha: 1.0),
        font: NSFont(name: "SF Mono", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        ansiColors: defaultLightAnsiColors,
        name: "Xcode Default (Light)",
        isDark: false
    )

    // MARK: - Default ANSI Colors

    /// ANSI color palette for dark themes (matches terminal defaults)
    private static let defaultDarkAnsiColors: [NSColor] = [
        // Normal colors (0-7)
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),         // 0: Black
        NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0),         // 1: Red
        NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0),         // 2: Green
        NSColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 1.0),         // 3: Yellow
        NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1.0),         // 4: Blue
        NSColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1.0),         // 5: Magenta
        NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1.0),         // 6: Cyan
        NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0),         // 7: White
        // Bright colors (8-15)
        NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0),         // 8: Bright Black
        NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0),         // 9: Bright Red
        NSColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1.0),         // 10: Bright Green
        NSColor(red: 1.0, green: 1.0, blue: 0.4, alpha: 1.0),         // 11: Bright Yellow
        NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0),         // 12: Bright Blue
        NSColor(red: 1.0, green: 0.4, blue: 1.0, alpha: 1.0),         // 13: Bright Magenta
        NSColor(red: 0.4, green: 1.0, blue: 1.0, alpha: 1.0),         // 14: Bright Cyan
        NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),         // 15: Bright White
    ]

    /// ANSI color palette for light themes
    private static let defaultLightAnsiColors: [NSColor] = [
        // Normal colors (0-7) - adjusted for light background
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),         // 0: Black
        NSColor(red: 0.6, green: 0.0, blue: 0.0, alpha: 1.0),         // 1: Red
        NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0),         // 2: Green
        NSColor(red: 0.5, green: 0.5, blue: 0.0, alpha: 1.0),         // 3: Yellow
        NSColor(red: 0.0, green: 0.0, blue: 0.7, alpha: 1.0),         // 4: Blue
        NSColor(red: 0.5, green: 0.0, blue: 0.5, alpha: 1.0),         // 5: Magenta
        NSColor(red: 0.0, green: 0.5, blue: 0.5, alpha: 1.0),         // 6: Cyan
        NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0),         // 7: White
        // Bright colors (8-15)
        NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0),         // 8: Bright Black
        NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0),         // 9: Bright Red
        NSColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 1.0),         // 10: Bright Green
        NSColor(red: 0.7, green: 0.7, blue: 0.0, alpha: 1.0),         // 11: Bright Yellow
        NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1.0),         // 12: Bright Blue
        NSColor(red: 0.7, green: 0.2, blue: 0.7, alpha: 1.0),         // 13: Bright Magenta
        NSColor(red: 0.2, green: 0.7, blue: 0.7, alpha: 1.0),         // 14: Bright Cyan
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),         // 15: Bright White (black for light theme)
    ]
}

// MARK: - Parsing Utilities

extension Theme {
    /// Parse color from Xcode theme format: "R G B A" (space-separated floats)
    static func parseColor(_ string: String) -> NSColor? {
        let components = string.split(separator: " ").compactMap { Double($0) }
        guard components.count >= 4 else { return nil }
        return NSColor(
            red: CGFloat(components[0]),
            green: CGFloat(components[1]),
            blue: CGFloat(components[2]),
            alpha: CGFloat(components[3])
        )
    }

    /// Parse font from Xcode theme format: "FontName - Size"
    static func parseFont(_ string: String) -> NSFont? {
        let parts = string.components(separatedBy: " - ")
        guard parts.count == 2,
              let size = Double(parts[1])
        else { return nil }

        let fontName = parts[0]
        // Try exact font name first, then fall back to system monospace
        return NSFont(name: fontName, size: CGFloat(size))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    /// Determine if a color is "dark" (for isDark detection)
    static func isDarkColor(_ color: NSColor) -> Bool {
        guard let rgbColor = color.usingColorSpace(.sRGB) else { return true }
        // Use perceived luminance formula
        let luminance = 0.299 * rgbColor.redComponent +
                       0.587 * rgbColor.greenComponent +
                       0.114 * rgbColor.blueComponent
        return luminance < 0.5
    }
}
