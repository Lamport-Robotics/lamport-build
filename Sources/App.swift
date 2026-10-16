import SwiftUI
import AppKit

@main
struct LamportBuildApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var desk = DeskModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(desk)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
                .background(WindowSetup())
                .task { await desk.loadMeta() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") { desk.newSession() }.keyboardShortcut("n")
                Button("Open Folder…") { desk.pickFolder() }.keyboardShortcut("o")
            }
            CommandMenu("Build") {
                Button("Run") { Task { await desk.startRun("installing and starting the project") } }.keyboardShortcut("r").disabled(!desk.canPreview || desk.isStatic)
                Button("Stop Run") { Task { await desk.runtime.stop() } }.keyboardShortcut(".", modifiers: [.command, .shift])
                Button("Stop Agent") { desk.stop() }.keyboardShortcut(".").disabled(!desk.busy)
                Divider()
                Button("Toggle Terminal") { desk.termOpen.toggle() }.keyboardShortcut("`")
                Button(desk.sideTab == 0 ? "Show Preview" : "Show Files") { desk.sideTab = desk.sideTab == 0 ? 1 : 0 }.keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandMenu("Account") {
                if desk.signedIn { Button("Sign Out\(desk.who.map { " (\($0))" } ?? "")") { desk.signOut() } } else { Button("Sign In…") { desk.signIn() } }
                Button("Open lamport.si") { NSWorkspace.shared.open(API.siteURL("/app")) }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// the window itself: our dark glass, draggable by its background, traffic lights floating over the rail
struct WindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(Theme.bg)
            w.isOpaque = true
            w.minSize = NSSize(width: 980, height: 640)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
