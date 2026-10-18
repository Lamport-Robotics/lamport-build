import SwiftUI

/// preferences: the lamport account, how much the agent may do on its own, and where the engine keeps its data
struct SettingsView: View {
    @EnvironmentObject var store: Store
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
        .frame(width: 520, height: 520)
    }
}
