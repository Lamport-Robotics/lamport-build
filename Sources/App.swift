import SwiftUI
import AppKit

@main
struct LamportBuildApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            Desk()
                .environmentObject(store)
                .environmentObject(store.engine)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
                .background(WindowSetup())
                .task { delegate.store = store; await store.boot() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands { DeskCommands(store: store) }
        Settings { SettingsView().environmentObject(store) }
    }
}

struct DeskCommands: Commands {
    @ObservedObject var store: Store
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") { store.newSession() }.keyboardShortcut("n")
            Button("Open Folder…") { store.pickFolder() }.keyboardShortcut("o")
        }
        CommandMenu("Session") {
            Button("Stop") { store.stop() }.keyboardShortcut(".").disabled(!store.isBusy)
            Divider()
            ForEach(Mode.allCases) { m in Button(m.title) { store.mode = m }.keyboardShortcut(KeyEquivalent(Character("\(Mode.allCases.firstIndex(of: m)! + 1)")), modifiers: [.command, .shift]) }
        }
        CommandMenu("View") {
            Button(store.sideOpen ? "Hide Side Panel" : "Show Side Panel") { store.sideOpen.toggle() }.keyboardShortcut("b", modifiers: [.command, .option])
            Button("Diff") { store.sideOpen = true; store.sideTab = .diff }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Terminal") { store.sideOpen = true; store.sideTab = .terminal }.keyboardShortcut("j", modifiers: [.command])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: Store?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidBecomeActive(_ notification: Notification) { NSApp.dockTile.badgeLabel = nil }
    private var signals: [DispatchSourceSignal] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")")
        // a kill or a logout must take the engine down with the app, not leave it listening
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.store?.engine.stop() }; exit(0) }
            src.resume()
            signals.append(src)
        }
    }
    func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { store?.engine.stop() } }
}

/// our dark window: transparent title bar, traffic lights over the sidebar, draggable by its background
struct WindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = false
            w.backgroundColor = NSColor(Theme.bg)
            w.styleMask.insert(.fullSizeContentView)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
