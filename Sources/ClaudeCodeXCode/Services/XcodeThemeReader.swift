import AppKit
import Combine

extension Notification.Name {
    static let themeDidChange = Notification.Name("com.claudecodexcode.themeDidChange")
}

/// Service that reads and monitors Xcode themes
/// Auto-detects current theme from Xcode preferences and watches for changes
@MainActor
final class XcodeThemeReader: ObservableObject {
    /// The currently active theme
    @Published private(set) var currentTheme: Theme = .xcodeDefaultDark

    private var themeWatcher: ThemeFileWatcher?
    private var appearanceObserver: NSObjectProtocol?
    private var xcodePrefsObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var xcodeDefaultsObserver: NSObjectProtocol?
    private var pollingTimer: Timer?

    /// Theme directory path
    private let themeDirectoryPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/Library/Developer/Xcode/UserData/FontAndColorThemes"
    }()

    init() {
        // Load initial theme
        currentTheme = loadCurrentTheme()
        // Start watching for changes
        startWatching()
    }

    // MARK: - Public API

    /// Reload the theme (can be called manually if needed)
    func reloadTheme() {
        let newTheme = loadCurrentTheme()
        if newTheme != currentTheme {
            currentTheme = newTheme
            print("[XcodeThemeReader] Theme changed to: \(newTheme.name)")
            // Post notification for non-SwiftUI observers (like FloatingPanel)
            NotificationCenter.default.post(
                name: .themeDidChange,
                object: nil,
                userInfo: ["theme": newTheme]
            )
        }
    }

    // MARK: - Theme Loading

    /// Load the current theme based on system appearance and Xcode preferences
    private func loadCurrentTheme() -> Theme {
        let isDarkMode = isSystemDarkMode()
        print("[XcodeThemeReader] System dark mode: \(isDarkMode)")

        // Try to get theme name from Xcode UserDefaults
        if let themeName = getXcodeThemeName(forDarkMode: isDarkMode) {
            print("[XcodeThemeReader] Got theme name: \(themeName)")
            if let theme = loadTheme(named: themeName, isDark: isDarkMode) {
                print("[XcodeThemeReader] Successfully loaded theme: \(theme.name), isDark: \(theme.isDark)")
                return theme
            } else {
                print("[XcodeThemeReader] Failed to load theme file for: \(themeName)")
            }
        } else {
            print("[XcodeThemeReader] No Xcode theme name found in UserDefaults")
        }

        // Fallback to built-in theme
        let fallback = isDarkMode ? Theme.xcodeDefaultDark : Theme.xcodeDefaultLight
        print("[XcodeThemeReader] Using fallback theme: \(fallback.name)")
        return fallback
    }

    /// Check if we should use dark mode (checks Xcode's preference first, then system)
    private func isSystemDarkMode() -> Bool {
        // First check Xcode's own appearance setting (IDEAppearance)
        // Values: 0 = System, 1 = Light, 2 = Dark
        if let xcodeDefaults = UserDefaults(suiteName: "com.apple.dt.Xcode") {
            let ideAppearance = xcodeDefaults.integer(forKey: "IDEAppearance")
            print("[XcodeThemeReader] Xcode IDEAppearance: \(ideAppearance) (0=System, 1=Light, 2=Dark)")

            switch ideAppearance {
            case 1:
                print("[XcodeThemeReader] Xcode set to Light mode")
                return false
            case 2:
                print("[XcodeThemeReader] Xcode set to Dark mode")
                return true
            default:
                // 0 or unset = follow system
                print("[XcodeThemeReader] Xcode set to follow System")
                break
            }
        }

        // Fall back to system appearance
        let appearance = NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        let isDark = match == .darkAqua
        print("[XcodeThemeReader] System appearance: \(appearance.name.rawValue), isDark: \(isDark)")
        return isDark
    }

    /// Get the current theme name from Xcode's UserDefaults
    private func getXcodeThemeName(forDarkMode isDark: Bool) -> String? {
        // Xcode stores preferences in com.apple.dt.Xcode domain
        guard let defaults = UserDefaults(suiteName: "com.apple.dt.Xcode") else {
            print("[XcodeThemeReader] Could not access Xcode UserDefaults")
            return nil
        }

        // Keys for dark/light mode themes
        let key = isDark ? "XCFontAndColorCurrentDarkTheme" : "XCFontAndColorCurrentTheme"
        print("[XcodeThemeReader] Looking for key: \(key)")

        if let themeName = defaults.string(forKey: key) {
            print("[XcodeThemeReader] Found Xcode theme preference: \(themeName)")
            return themeName
        }

        // Try alternate key format
        let altKey = isDark ? "DVTFontAndColorCurrentDarkTheme" : "DVTFontAndColorCurrentTheme"
        print("[XcodeThemeReader] Trying alternate key: \(altKey)")
        if let themeName = defaults.string(forKey: altKey) {
            print("[XcodeThemeReader] Found Xcode theme preference (alt): \(themeName)")
            return themeName
        }

        // Debug: dump all keys containing "Theme" or "Font"
        print("[XcodeThemeReader] Dumping Xcode UserDefaults keys containing Theme/Font/Color:")
        let dict = defaults.dictionaryRepresentation()
        for (key, value) in dict {
            if key.contains("Theme") || key.contains("Font") || key.contains("Color") {
                print("  \(key): \(value)")
            }
        }

        return nil
    }

    /// Load a theme from the theme directory
    private func loadTheme(named name: String, isDark: Bool) -> Theme? {
        // Build path to theme file
        let themeFileName = name.hasSuffix(".xccolortheme") ? name : "\(name).xccolortheme"
        let themePath = "\(themeDirectoryPath)/\(themeFileName)"
        let themeURL = URL(fileURLWithPath: themePath)

        guard FileManager.default.fileExists(atPath: themePath) else {
            print("[XcodeThemeReader] Theme file not found: \(themePath)")
            return nil
        }

        return parseThemeFile(at: themeURL, name: name, isDarkHint: isDark)
    }

    // MARK: - Theme Parsing

    /// Parse an .xccolortheme plist file
    private func parseThemeFile(at url: URL, name: String, isDarkHint: Bool) -> Theme? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            print("[XcodeThemeReader] Failed to parse theme file: \(url.path)")
            return nil
        }

        // Extract colors - prefer console colors, fall back to source text colors
        let backgroundColor = extractColor(from: plist, keys: [
            "DVTConsoleTextBackgroundColor",
            "DVTSourceTextBackground"
        ]) ?? (isDarkHint ? Theme.xcodeDefaultDark.backgroundColor : Theme.xcodeDefaultLight.backgroundColor)

        let foregroundColor = extractColor(from: plist, keys: [
            "DVTConsoleDebuggerOutputTextColor",
            "DVTSourceTextForeground"
        ]) ?? (isDarkHint ? Theme.xcodeDefaultDark.foregroundColor : Theme.xcodeDefaultLight.foregroundColor)

        let cursorColor = extractColor(from: plist, keys: [
            "DVTConsoleTextInsertionPointColor",
            "DVTSourceTextInsertionPointColor"
        ]) ?? (isDarkHint ? Theme.xcodeDefaultDark.cursorColor : Theme.xcodeDefaultLight.cursorColor)

        let selectionColor = extractColor(from: plist, keys: [
            "DVTConsoleTextSelectionColor",
            "DVTSourceTextSelectionColor"
        ]) ?? (isDarkHint ? Theme.xcodeDefaultDark.selectionColor : Theme.xcodeDefaultLight.selectionColor)

        // Extract font
        let font = extractFont(from: plist, keys: [
            "DVTConsoleDebuggerOutputTextFont",
            "DVTSourceTextFont"
        ]) ?? (isDarkHint ? Theme.xcodeDefaultDark.font : Theme.xcodeDefaultLight.font)

        // Determine if theme is dark based on background color
        let isDark = Theme.isDarkColor(backgroundColor)

        // Use default ANSI colors (Xcode themes don't typically define these)
        let ansiColors = isDark ? Theme.xcodeDefaultDark.ansiColors : Theme.xcodeDefaultLight.ansiColors

        return Theme(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            cursorColor: cursorColor,
            selectionColor: selectionColor,
            font: font,
            ansiColors: ansiColors,
            name: name,
            isDark: isDark
        )
    }

    /// Extract a color from plist, trying multiple keys
    private func extractColor(from plist: [String: Any], keys: [String]) -> NSColor? {
        for key in keys {
            if let colorString = plist[key] as? String,
               let color = Theme.parseColor(colorString) {
                return color
            }
        }
        return nil
    }

    /// Extract a font from plist, trying multiple keys
    private func extractFont(from plist: [String: Any], keys: [String]) -> NSFont? {
        for key in keys {
            if let fontString = plist[key] as? String,
               let font = Theme.parseFont(fontString) {
                return font
            }
        }
        return nil
    }

    // MARK: - File Watching

    /// Start watching for theme changes
    func startWatching() {
        // Watch theme directory for file changes
        themeWatcher = ThemeFileWatcher(watching: [themeDirectoryPath]) { [weak self] in
            Task { @MainActor in
                self?.reloadTheme()
            }
        }
        themeWatcher?.start()

        // Watch for system dark/light mode changes via DistributedNotificationCenter
        // This is the proper way to detect appearance changes
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Small delay to let the system finish updating
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                self?.reloadTheme()
            }
        }

        // Also watch via workspace notification as backup
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadTheme()
            }
        }

        // Watch for Xcode preference changes via DistributedNotificationCenter
        xcodePrefsObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.dt.Xcode.PreferenceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadTheme()
            }
        }

        // Poll Xcode preferences every 2 seconds (since there's no reliable notification)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadTheme()
            }
        }

        print("[XcodeThemeReader] Started watching for theme changes")
    }

    /// Stop watching for theme changes
    nonisolated func stopWatching() {
        // Note: This is nonisolated to allow cleanup from various contexts
        // The actual cleanup of MainActor properties happens via Task
        Task { @MainActor [weak self] in
            self?.performStopWatching()
        }
    }

    /// Actually perform the stop watching cleanup (must be called on MainActor)
    private func performStopWatching() {
        themeWatcher?.stop()
        themeWatcher = nil

        pollingTimer?.invalidate()
        pollingTimer = nil

        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            appearanceObserver = nil
        }

        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }

        if let observer = xcodePrefsObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            xcodePrefsObserver = nil
        }

        print("[XcodeThemeReader] Stopped watching for theme changes")
    }
}
