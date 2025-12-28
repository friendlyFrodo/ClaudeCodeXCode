import SwiftUI

/// Settings view for app preferences
struct SettingsView: View {
    @AppStorage("globalHotkey") private var globalHotkey: String = "⌘⇧C"
    @AppStorage("autoLaunchWithXcode") private var autoLaunchWithXcode: Bool = false
    @AppStorage("floatAboveAll") private var floatAboveAll: Bool = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Float above all windows", isOn: $floatAboveAll)
                Toggle("Auto-launch with Xcode", isOn: $autoLaunchWithXcode)
            }

            Section("Keyboard Shortcut") {
                HStack {
                    Text("Toggle Panel")
                    Spacer()
                    Text(globalHotkey)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
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
        .frame(width: 400, height: 300)
    }
}

#Preview {
    SettingsView()
}
