import SwiftUI

/// preferences: where the desk lives, the default model, approvals, notifications
struct SettingsView: View {
    @AppStorage("apiBase") var apiBase = "https://lamport.si"
    @AppStorage("defaultModel") var defaultModel = "glm-5.3-flash"
    @AppStorage("notify") var notify = true
    @AppStorage("autoApproveAll") var autoApproveAll = false
    @AppStorage("alwaysAllow") var alwaysAllowJSON = "[]"
    @AppStorage("openSideOnRun") var openSideOnRun = true
    @State private var newRule = ""
    var rules: [String] { (try? JSONDecoder().decode([String].self, from: Data(alwaysAllowJSON.utf8))) ?? [] }
    func setRules(_ r: [String]) { alwaysAllowJSON = String(data: (try? JSONEncoder().encode(r)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }
    var body: some View {
        Form {
            Section("Account") {
                TextField("Server", text: $apiBase).help("The Lamport server the app talks to. Leave as is unless you run your own.")
                if let who = UserDefaults.standard.string(forKey: "who") { LabeledContent("Signed in as", value: who) }
                LabeledContent("Log file", value: Log.file.path).font(.caption).foregroundStyle(.secondary)
            }
            Section("Agent") {
                Picker("Default model", selection: $defaultModel) {
                    ForEach(["glm-5.3-flash", "deepseek-v4.1-flash", "gpt-oss-120b", "mimo-v2.6-flash", "qwen3-coder-30b", "lamport"], id: \.self) { Text($0 == "lamport" ? "Lamport SI (Pro)" : $0).tag($0) }
                }
                Toggle("Open the preview when a run starts", isOn: $openSideOnRun)
            }
            Section("Approvals") {
                Toggle("Run every command without asking", isOn: $autoApproveAll)
                Text("Off by default. Commands that delete, push, publish, deploy, move funds or read secrets pause for your approval.").font(.caption).foregroundStyle(.secondary)
                ForEach(rules, id: \.self) { r in HStack { Text(r).font(.system(.body, design: .monospaced)); Spacer(); Button("Remove") { setRules(rules.filter { $0 != r }) }.buttonStyle(.link) } }
                HStack { TextField("Always allow commands starting with…", text: $newRule).font(.system(.body, design: .monospaced)); Button("Add") { let t = newRule.trimmingCharacters(in: .whitespaces); if !t.isEmpty { setRules(rules + [t]); newRule = "" } }.disabled(newRule.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            Section("Notifications") {
                Toggle("Notify when a turn finishes or needs approval while the app is in the background", isOn: $notify)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
    }
}
