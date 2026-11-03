import SwiftUI
import Sparkle

/// preferences: the lamport account, how much the agent may do on its own, the folders, updates, and where things are kept
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var autoUpdate = (NSApp.delegate as? AppDelegate)?.updates.updater.automaticallyChecksForUpdates ?? true
    var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") + ")" }
    var body: some View {
        Form {
            Section("Account") {
                if store.signedIn {
                    LabeledContent("Signed in", value: store.who ?? "Lamport member")
                    if let u = store.usage {
                        LabeledContent("Plan", value: u.pro ? "Pro" : "Free")
                        LabeledContent("Today", value: "\(u.turns) of \(u.turnLimit) turns · \(Store.tokens(u.tokens)) of \(Store.tokens(u.tokenLimit)) tokens")
                    }
                    HStack { Text("Models run through lamport.si with this Mac's own key. No provider keys are stored here.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Sign Out") { store.signOut() } }
                } else {
                    HStack {
                        Text(store.signingIn ? "Waiting for the browser…" : "Sign in to use Lamport's models. Free members get a daily allowance; Lamport SI comes with Pro.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if store.signingIn { Button("Cancel") { store.cancelSignIn() } } else { Button("Sign In") { store.signIn() }.keyboardShortcut(.defaultAction) }
                    }
                    if let e = store.authError { Text(e).font(.caption).foregroundStyle(Theme.red) }
                }
            }
            Section("Agent") {
                Picker("Permissions", selection: $store.mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                Text("Ask before edits pauses on every file change and command. Bypass runs everything without asking; only use it in a folder you can throw away.").font(.caption).foregroundStyle(.secondary)
                if let m = store.model { LabeledContent("Model", value: m.name + (m.isLocal ? " · on this Mac" : "")) }
            }
            Section("Folders") {
                if store.projects.isEmpty { Text("No folders yet. Open one from the sidebar or with ⌘O.").font(.caption).foregroundStyle(.secondary) }
                ForEach(store.projects) { p in
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            Text(Store.short(p.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.path)]) }.buttonStyle(.link)
                        Button("Remove") { store.removeProject(p) }.buttonStyle(.link)
                    }
                }
                Button("Open folder…") { store.pickFolder() }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, on in (NSApp.delegate as? AppDelegate)?.updates.updater.automaticallyChecksForUpdates = on }
                HStack {
                    Text("Updates come from lamport.si, signed with Lamport's key.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { (NSApp.delegate as? AppDelegate)?.updates.updater.checkForUpdates() }
                }
            }
            Section("Support") {
                LabeledContent("Version", value: version)
                HStack { LabeledContent("Engine data", value: Store.short(Engine.home.path)).font(.caption); Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([Engine.home]) }.buttonStyle(.link) }
                HStack { LabeledContent("Log file", value: Store.short(Log.file.path)).font(.caption); Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([Log.file]) }.buttonStyle(.link) }
                HStack {
                    Button("Keyboard Shortcuts…") { store.shortcuts = true }
                    Button("Source on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/Lamport-Robotics/lamport-build")!) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 620)
    }
}
