import SwiftUI
import Security

/// Settings view for app preferences
struct SettingsView: View {
    @AppStorage("globalHotkey") private var globalHotkey: String = "⌘⇧C"
    @AppStorage("autoLaunchWithXcode") private var autoLaunchWithXcode: Bool = false
    @AppStorage("floatAboveAll") private var floatAboveAll: Bool = true
    @AppStorage("whisperEnabled") private var whisperEnabled: Bool = true
    @AppStorage("whisperFrequency") private var whisperFrequency: Double = 45

    @State private var apiKey: String = ""
    @State private var apiKeyStatus: String = ""
    @State private var showingApiKey: Bool = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Float above all windows", isOn: $floatAboveAll)
                Toggle("Auto-launch with Xcode", isOn: $autoLaunchWithXcode)
            }

            Section("AI Pair Programmer (Whispers)") {
                Toggle("Enable whispers", isOn: $whisperEnabled)

                HStack {
                    Text("Min. interval")
                    Spacer()
                    Text("\(Int(whisperFrequency))s")
                        .foregroundColor(.secondary)
                    Slider(value: $whisperFrequency, in: 15...120, step: 5)
                        .frame(width: 150)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Anthropic API Key")
                        Spacer()
                        if !apiKeyStatus.isEmpty {
                            Text(apiKeyStatus)
                                .font(.caption)
                                .foregroundColor(apiKeyStatus.contains("✓") ? .green : .orange)
                        }
                    }

                    HStack {
                        if showingApiKey {
                            TextField("sk-ant-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showingApiKey.toggle() }) {
                            Image(systemName: showingApiKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        Button("Save Key") {
                            saveApiKey()
                        }
                        .disabled(apiKey.isEmpty)

                        if KeychainHelper.hasApiKey() {
                            Button("Clear Key") {
                                clearApiKey()
                            }
                            .foregroundColor(.red)
                        }
                    }

                    Text("Required for AI whispers. Get your key at console.anthropic.com")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Keyboard Shortcuts") {
                HStack {
                    Text("Toggle Panel")
                    Spacer()
                    Text(globalHotkey)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }

                Group {
                    shortcutRow("Apply whisper", shortcut: "⌘Y")
                    shortcutRow("Tell me more", shortcut: "⌘?")
                    shortcutRow("Dismiss whisper", shortcut: "⌘N")
                }
                .foregroundColor(.secondary)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                Link("GitHub Repository",
                     destination: URL(string: "https://github.com/friendlyFrodo/ClaudeCodeXCode")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
        .onAppear {
            loadApiKeyStatus()
        }
    }

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)
        }
    }

    private func loadApiKeyStatus() {
        if KeychainHelper.hasApiKey() {
            apiKeyStatus = "✓ Saved in Keychain"
        } else if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil {
            apiKeyStatus = "✓ From environment"
        } else {
            apiKeyStatus = "Not configured"
        }
    }

    private func saveApiKey() {
        guard !apiKey.isEmpty else { return }

        if KeychainHelper.saveApiKey(apiKey) {
            apiKeyStatus = "✓ Saved in Keychain"
            apiKey = ""  // Clear the field after saving
            // Notify HaikuClient to reload
            NotificationCenter.default.post(name: .apiKeyChanged, object: nil)
        } else {
            apiKeyStatus = "Failed to save"
        }
    }

    private func clearApiKey() {
        KeychainHelper.deleteApiKey()
        apiKeyStatus = "Not configured"
        NotificationCenter.default.post(name: .apiKeyChanged, object: nil)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let apiKeyChanged = Notification.Name("com.claudecodexcode.apiKeyChanged")
}

// MARK: - Keychain Helper

enum KeychainHelper {
    private static let service = "com.claudecodexcode"
    private static let account = "anthropic-api-key"

    static func saveApiKey(_ key: String) -> Bool {
        // Delete existing first
        deleteApiKey()

        let data = key.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func loadApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return key
    }

    static func deleteApiKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    static func hasApiKey() -> Bool {
        loadApiKey() != nil
    }
}

#Preview {
    SettingsView()
}
