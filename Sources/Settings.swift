import SwiftUI

/// preferences: how much the agent may do on its own, and where the engine keeps its data
struct SettingsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Form {
            Section("Agent") {
                Picker("Default permissions", selection: $store.mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                Text("Ask before edits pauses on every file change and command. Bypass runs everything without asking; only use it in a folder you can throw away.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Folders") {
                ForEach(store.projects) { p in
                    HStack { Text(Store.short(p.path)).font(.system(.body, design: .monospaced)); Spacer(); Button("Remove") { store.removeProject(p) }.buttonStyle(.link) }
                }
            }
            Section("Support") {
                LabeledContent("Engine data", value: Store.short(Engine.home.path)).font(.caption)
                LabeledContent("Log file", value: Store.short(Log.file.path)).font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 440)
    }
}
