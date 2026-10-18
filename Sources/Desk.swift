import SwiftUI

/// the window: sessions on the left, the conversation in the middle, diff and terminal on the right
struct Desk: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @State private var sideWidth: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "sideWidth")).clamped(360, 820, or: 460)
    @State private var sidebar = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebar {
                Sidebar().frame(width: 252)
                Rectangle().fill(Theme.line).frame(width: 1)
            }
            ZStack {
                Theme.main
                switch engine.state {
                case .starting: Starting()
                case .failed(let why): EngineDown(why: why)
                case .ready: Conversation(sidebar: $sidebar)
                }
            }
            if store.sideOpen, engine.state == .ready, store.directory != nil {
                Splitter(width: $sideWidth)
                SidePane().frame(width: sideWidth)
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                Text(t).font(Theme.sans(12.5)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Color(hex: 0x2a2a2a))).overlay(Capsule().strokeBorder(Theme.line2))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.toast)
        .animation(.easeOut(duration: 0.18), value: store.sideOpen)
    }
}

/// the drag handle between the conversation and the side panel
struct Splitter: View {
    @Binding var width: CGFloat
    @State private var start: CGFloat?
    var body: some View {
        Rectangle().fill(Theme.line).frame(width: 1)
            .overlay(Color.clear.frame(width: 9).contentShape(Rectangle())
                .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    if start == nil { start = width }
                    width = ((start ?? width) - g.translation.width).clamped(340, 900, or: 460)
                }.onEnded { _ in start = nil; UserDefaults.standard.set(Double(width), forKey: "sideWidth") }))
    }
}

struct Starting: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Starting the engine").font(Theme.sans(12.5)).foregroundStyle(Theme.mute)
        }
    }
}

struct EngineDown: View {
    var why: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 20)).foregroundStyle(Theme.amber)
            Text(why).font(Theme.sans(13)).foregroundStyle(Theme.ink2)
            Text("Details are in \(Store.short(Log.file.path))").font(Theme.sans(11.5)).foregroundStyle(Theme.dim)
        }
    }
}

// MARK: sidebar

struct Sidebar: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 40)
            VStack(spacing: 2) {
                Button { store.newSession() } label: {
                    Row(icon: "square.and.pencil", title: "New session", hint: "⌘N")
                }.buttonStyle(Flat(pad: 8))
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.dim)
                    TextField("Search sessions", text: $store.search).textFieldStyle(.plain).font(Theme.sans(12.5)).foregroundStyle(Theme.ink2)
                }
                .padding(.horizontal, 8).frame(height: 28)
            }
            .padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.projects) { p in ProjectSection(project: p) }
                    if store.projects.isEmpty {
                        Text("Open a folder to start. Each folder keeps its own sessions.")
                            .font(Theme.sans(12)).foregroundStyle(Theme.dim).padding(.horizontal, 16).padding(.top, 8)
                    }
                }
                .padding(.vertical, 12)
            }

            Rectangle().fill(Theme.line).frame(height: 1)
            Account().padding(.horizontal, 8).padding(.top, 8)
            HStack(spacing: 4) {
                Button { store.pickFolder() } label: { Row(icon: "folder.badge.plus", title: "Open folder…", hint: "⌘O") }.buttonStyle(Flat(pad: 8))
                SettingsLink { Image(systemName: "gearshape").font(.system(size: 12.5)).foregroundStyle(Theme.mute).frame(width: 28, height: 28) }.buttonStyle(Flat(pad: 0))
            }
            .padding(8)
        }
        .background(Theme.bg)
    }
}

/// who the app is signed in as, and today's allowance; signed out, the way in
struct Account: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if store.signedIn {
            Menu {
                if let u = store.usage { Text(u.pro ? "Pro" : "Free plan") ; Text("\(u.turnsLeft) of \(u.turnLimit) turns left today") }
                Divider()
                Button("Sign Out") { store.signOut() }
            } label: {
                HStack(spacing: 9) {
                    Text(String((store.who ?? "L").prefix(1)).uppercased()).font(Theme.sans(10.5, .semibold)).foregroundStyle(Theme.ink)
                        .frame(width: 20, height: 20).background(Circle().fill(Theme.raised)).overlay(Circle().strokeBorder(Theme.line2))
                    Text(store.who ?? "Signed in").font(Theme.sans(12.5)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let u = store.usage { Text(u.pro ? "Pro" : "\(u.turnsLeft) left").font(Theme.sans(11)).foregroundStyle(Theme.dim) }
                }
                .padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button { store.signingIn ? store.cancelSignIn() : store.signIn() } label: {
                    Row(icon: "person.crop.circle", title: store.signingIn ? "Waiting for the browser…" : "Sign in", hint: store.signingIn ? "Cancel" : nil)
                }.buttonStyle(Flat(pad: 8))
                if let e = store.authError { Text(e).font(Theme.sans(11)).foregroundStyle(Theme.red).padding(.horizontal, 8).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

struct Row: View {
    var icon: String; var title: String; var hint: String? = nil
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 12.5)).foregroundStyle(Theme.ink2).frame(width: 16)
            Text(title).font(Theme.sans(13)).foregroundStyle(Theme.ink)
            Spacer()
            if let hint { Text(hint).font(Theme.sans(11)).foregroundStyle(Theme.dim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProjectSection: View {
    @EnvironmentObject var store: Store
    var project: Project
    @State private var open = true
    @State private var showAll = false
    var body: some View {
        let rows = store.rows(for: project)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Button { open.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 10)
                        Text(project.name).font(Theme.sans(11.5, .semibold)).foregroundStyle(Theme.mute).lineLimit(1)
                    }
                }.buttonStyle(Quiet())
                Spacer()
                Button { store.newSession(in: project.path) } label: { Image(systemName: "plus").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.mute) }
                    .buttonStyle(Flat(pad: 4)).help("New session in \(project.name)")
            }
            .padding(.horizontal, 16).padding(.bottom, 3)
            .contextMenu {
                Button("New Session") { store.newSession(in: project.path) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)]) }
                Divider()
                Button("Remove from Sidebar") { store.removeProject(project) }
            }
            if open {
                if store.draftProject == project.path && store.current == nil {
                    SessionItem(title: "New session", sub: nil, selected: true, busy: false, ask: false)
                }
                ForEach(showAll ? rows : Array(rows.prefix(8))) { r in
                    Button { store.open(r.id) } label: {
                        SessionItem(title: r.title, sub: ago(r.updated), selected: store.current == r.id, busy: store.busy.contains(r.id), ask: store.asks.contains { $0.sessionID == r.id })
                    }
                    .buttonStyle(Quiet())
                    .contextMenu {
                        Button("Rename…") { rename(r) }
                        Button("Delete", role: .destructive) { store.delete(r) }
                    }
                }
                if rows.count > 8 {
                    Button(showAll ? "Show less" : "Show \(rows.count - 8) more") { showAll.toggle() }
                        .buttonStyle(Quiet()).font(Theme.sans(11.5)).foregroundStyle(Theme.dim).padding(.horizontal, 26).padding(.top, 2)
                }
            }
        }
    }
    func rename(_ r: SessionRow) {
        let a = NSAlert()
        a.messageText = "Rename session"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); f.stringValue = r.title
        a.accessoryView = f
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { store.rename(r, to: f.stringValue) }
    }
}

struct SessionItem: View {
    var title: String; var sub: String?; var selected: Bool; var busy: Bool; var ask: Bool
    @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if ask { Circle().fill(Theme.amber).frame(width: 6, height: 6) }
                else if busy { ProgressView().controlSize(.mini).scaleEffect(0.7) }
                else { Color.clear }
            }
            .frame(width: 10, height: 10)
            Text(title).font(Theme.sans(12.5)).foregroundStyle(selected ? Theme.ink : Theme.ink2).lineLimit(1)
            Spacer(minLength: 4)
            if let sub { Text(sub).font(Theme.sans(11)).foregroundStyle(Theme.dim) }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Theme.selected : hover ? Theme.hover : .clear))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat, or fallback: CGFloat) -> CGFloat { self == 0 || !isFinite ? fallback : Swift.min(Swift.max(self, lo), hi) }
}
