import SwiftUI

/// the window: sessions on the left, the conversation in the middle, diff, files and terminal on the right
struct Desk: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @State private var sideWidth: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "sideWidth")).clamped(360, 820, or: 460)

    var body: some View {
        HStack(spacing: 0) {
            if store.sidebar {
                Sidebar().frame(width: 252)
                Rectangle().fill(Theme.line).frame(width: 1)
            }
            ZStack {
                Theme.main
                switch engine.state {
                case .starting: Starting()
                case .failed(let why): EngineDown(why: why)
                case .ready: Conversation(sidebar: $store.sidebar)
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
        .overlay { if store.palette { Palette() } }
        .sheet(isPresented: $store.shortcuts) { ShortcutsSheet() }
        .animation(.easeOut(duration: 0.18), value: store.toast)
        .animation(.easeOut(duration: 0.18), value: store.sideOpen)
        .animation(.easeOut(duration: 0.12), value: store.palette)
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
        VStack(spacing: 14) {
            Image("Mark").resizable().interpolation(.high).scaledToFit().frame(height: 30).opacity(0.5)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting the engine").font(Theme.sans(12.5)).foregroundStyle(Theme.mute)
            }
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
            Button("Show the log") { NSWorkspace.shared.activateFileViewerSelecting([Log.file]) }.buttonStyle(Secondary()).padding(.top, 6)
        }
    }
}

// MARK: sidebar

struct Sidebar: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Brand().frame(height: 40).padding(.leading, 80)
            VStack(spacing: 2) {
                Button { store.newSession() } label: {
                    Row(icon: "square.and.pencil", title: "New session", hint: "⌘N")
                }.buttonStyle(Flat(pad: 8))
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.dim)
                    TextField("Search sessions", text: $store.search).textFieldStyle(.plain).font(Theme.sans(12.5)).foregroundStyle(Theme.ink2)
                    if !store.search.isEmpty {
                        Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.dim) }.buttonStyle(Quiet())
                    }
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
            Account().padding(.horizontal, 8).padding(.top, 10)
            HStack(spacing: 4) {
                Button { store.pickFolder() } label: { Row(icon: "folder.badge.plus", title: "Open folder…", hint: "⌘O") }.buttonStyle(Flat(pad: 8))
                Button { store.palette = true } label: { Image(systemName: "command").font(.system(size: 12)).foregroundStyle(Theme.mute).frame(width: 28, height: 28) }.buttonStyle(Flat(pad: 0)).help("Commands  ⌘K")
                SettingsLink { Image(systemName: "gearshape").font(.system(size: 12.5)).foregroundStyle(Theme.mute).frame(width: 28, height: 28) }.buttonStyle(Flat(pad: 0)).help("Settings  ⌘,")
            }
            .padding(8)
        }
        .background(Theme.bg)
    }
}

/// who the app is signed in as, and today's allowance; signed out, the way in
struct Account: View {
    @EnvironmentObject var store: Store
    @State private var open = false
    var body: some View {
        if store.signedIn {
            Button { open.toggle() } label: {
                HStack(spacing: 9) {
                    Avatar(who: store.who, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.who ?? "Lamport member").font(Theme.sans(12.5, .medium)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                        Text(store.usage.map { $0.pro ? "Pro" : "Free · \($0.turnsLeft) turns left" } ?? "Signed in").font(Theme.sans(11)).foregroundStyle(Theme.mute).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 8).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(open ? Theme.selected : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(Quiet())
            .popover(isPresented: $open, arrowEdge: .top) { AccountCard(close: { open = false }).environmentObject(store) }
            .task { await store.refreshUsage() }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to use Lamport's models. Free members get a daily allowance.")
                    .font(Theme.sans(11.5)).foregroundStyle(Theme.mute).fixedSize(horizontal: false, vertical: true)
                Button { store.signingIn ? store.cancelSignIn() : store.signIn() } label: {
                    HStack(spacing: 7) {
                        if store.signingIn { ProgressView().controlSize(.mini) } else { Image("Mark").resizable().renderingMode(.template).scaledToFit().frame(height: 11) }
                        Text(store.signingIn ? "Waiting for the browser… Cancel" : "Sign in with Lamport")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(Primary())
                if let e = store.authError { Text(e).font(Theme.sans(11)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        }
    }
}

/// the member's initial in the brand's cream
struct Avatar: View {
    var who: String?; var size: CGFloat
    var body: some View {
        Text(String((who ?? "L").prefix(1)).uppercased())
            .font(Theme.sans(size * 0.46, .medium)).foregroundStyle(Color(hex: 0x141414))
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.cream))
    }
}

/// the account, opened from the sidebar: plan, today's use, the way out
struct AccountCard: View {
    @EnvironmentObject var store: Store
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Avatar(who: store.who, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.who ?? "Lamport member").font(Theme.sans(13, .medium)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                    Text(store.usage.map { $0.pro ? "Pro plan" : "Free plan" } ?? "Lamport account").font(Theme.sans(11.5)).foregroundStyle(Theme.mute)
                }
                Spacer()
                if let u = store.usage {
                    Text(u.pro ? "PRO" : "FREE").font(Theme.sans(9.5, .medium)).tracking(0.8)
                        .foregroundStyle(u.pro ? Color(hex: 0x141414) : Theme.ink2)
                        .padding(.horizontal, 7).frame(height: 18)
                        .background(Capsule().fill(u.pro ? Theme.cream : Color.white.opacity(0.08)))
                }
            }
            if let u = store.usage {
                VStack(alignment: .leading, spacing: 10) {
                    Meter(title: "Turns today", used: u.turns, limit: u.turnLimit, label: "\(u.turns) of \(u.turnLimit)")
                    Meter(title: "Tokens today", used: u.tokens, limit: u.tokenLimit, label: "\(Store.tokens(u.tokens)) of \(Store.tokens(u.tokenLimit))")
                }
            } else {
                Text("Today's usage shows up here once lamport.si reports it.").font(Theme.sans(11.5)).foregroundStyle(Theme.dim)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            VStack(spacing: 2) {
                Button { NSWorkspace.shared.open(API.siteURL("/app")); close() } label: { Row(icon: "arrow.up.right.square", title: "Open lamport.si") }.buttonStyle(Flat(pad: 7))
                SettingsLink { Row(icon: "gearshape", title: "Settings…", hint: "⌘,") }.buttonStyle(Flat(pad: 7))
                Button { close(); store.shortcuts = true } label: { Row(icon: "keyboard", title: "Keyboard shortcuts", hint: "⌘/") }.buttonStyle(Flat(pad: 7))
                Button { close(); store.signOut() } label: { Row(icon: "rectangle.portrait.and.arrow.right", title: "Sign out") }.buttonStyle(Flat(pad: 7))
            }
        }
        .padding(16)
        .frame(width: 290)
        .background(Theme.raised)
    }
}

struct Meter: View {
    var title: String; var used: Int; var limit: Int; var label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title).foregroundStyle(Theme.mute); Spacer(); Text(label).foregroundStyle(Theme.ink2) }.font(Theme.sans(11.5))
            GeometryReader { g in
                let f = limit > 0 ? min(1, CGFloat(used) / CGFloat(limit)) : 0
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) { Capsule().fill(f > 0.9 ? Theme.amber : Theme.cream).frame(width: max(4, g.size.width * f)) }
            }
            .frame(height: 4)
        }
    }
}

/// the mark and the name, set in the title bar beside the traffic lights
struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("Mark").resizable().interpolation(.high).scaledToFit().frame(height: 18)
            (Text("Lamport").foregroundStyle(Theme.ink) + Text(" Build").foregroundStyle(Theme.mute)).font(Theme.sans(13, .medium))
            Spacer()
        }
        .padding(.top, 2)
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
                Button { withAnimation(.easeOut(duration: 0.12)) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 10).rotationEffect(.degrees(open ? 90 : 0))
                        Text(project.name).font(Theme.sans(11.5, .medium)).foregroundStyle(Theme.mute).lineLimit(1)
                    }
                }.buttonStyle(Quiet()).help(Store.short(project.path))
                Spacer()
                Button { store.newSession(in: project.path) } label: { Image(systemName: "plus").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.mute) }
                    .buttonStyle(Flat(pad: 4)).help("New session in \(project.name)")
            }
            .padding(.horizontal, 16).padding(.bottom, 3)
            .contextMenu {
                Button("New Session") { store.newSession(in: project.path) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)]) }
                Button("Open in Terminal") { store.openInTerminal(project.path) }
                Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(project.path, forType: .string) }
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
                        Button("Fork") { store.fork(r) }
                        Divider()
                        Button("Delete", role: .destructive) { store.delete(r) }
                    }
                }
                if rows.count > 8 {
                    Button(showAll ? "Show less" : "Show \(rows.count - 8) more") { withAnimation(.easeOut(duration: 0.12)) { showAll.toggle() } }
                        .buttonStyle(Quiet()).font(Theme.sans(11.5)).foregroundStyle(Theme.dim).padding(.horizontal, 26).padding(.top, 2)
                }
                if rows.isEmpty, !(store.draftProject == project.path && store.current == nil) {
                    Text(store.query.isEmpty ? "No sessions yet" : "No matches").font(Theme.sans(11.5)).foregroundStyle(Theme.dim).padding(.horizontal, 26).padding(.vertical, 4)
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

// MARK: the command palette

struct Action: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let icon: String
    let keys: String?
    let run: () -> Void
}

struct Palette: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var pick = 0
    @FocusState private var focused: Bool

    var actions: [Action] {
        var out: [Action] = [
            Action(id: "new", title: "New session", detail: store.directory.map { URL(fileURLWithPath: $0).lastPathComponent }, icon: "square.and.pencil", keys: "⌘N") { store.newSession() },
            Action(id: "open", title: "Open folder…", detail: nil, icon: "folder.badge.plus", keys: "⌘O") { store.pickFolder() },
            Action(id: "diff", title: "Show diff", detail: nil, icon: "plusminus", keys: "⇧⌘D") { store.sideTab = .diff; store.sideOpen = true },
            Action(id: "files", title: "Show files", detail: nil, icon: "doc.text", keys: "⇧⌘E") { store.sideTab = .files; store.sideOpen = true },
            Action(id: "term", title: "Show terminal", detail: nil, icon: "terminal", keys: "⌘J") { store.sideTab = .terminal; store.sideOpen = true },
            Action(id: "side", title: store.sideOpen ? "Hide side panel" : "Show side panel", detail: nil, icon: "sidebar.right", keys: "⌥⌘B") { store.sideOpen.toggle() },
            Action(id: "sidebar", title: store.sidebar ? "Hide sidebar" : "Show sidebar", detail: nil, icon: "sidebar.left", keys: "⌘\\") { store.sidebar.toggle() },
        ]
        for m in Mode.allCases { out.append(Action(id: "mode-\(m.rawValue)", title: "Permissions: \(m.title)", detail: m == store.mode ? "current" : nil, icon: m.icon, keys: "⇧⌘\(Mode.allCases.firstIndex(of: m)! + 1)") { store.mode = m }) }
        for m in store.models where !m.locked { out.append(Action(id: "model-\(m.key)", title: "Model: \(m.name)", detail: m == store.model ? "current" : (m.isLocal ? "on this Mac" : "Lamport"), icon: "cpu", keys: nil) { store.choose(m) }) }
        if store.current != nil {
            out.append(Action(id: "compact", title: "Compact the context", detail: "fold the history into a summary", icon: "arrow.down.right.and.arrow.up.left", keys: nil) { store.compact() })
            if let r = store.currentRow { out.append(Action(id: "fork", title: "Fork this session", detail: nil, icon: "arrow.triangle.branch", keys: nil) { store.fork(r) }) }
        }
        for c in store.commands { out.append(Action(id: "cmd-\(c.name)", title: "/" + c.name, detail: c.description, icon: "command", keys: nil) { store.draftText = "/" + c.name + " " }) }
        if let d = store.directory {
            out.append(Action(id: "finder", title: "Show folder in Finder", detail: Store.short(d), icon: "folder", keys: nil) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: d)]) })
            out.append(Action(id: "terminal-app", title: "Open folder in Terminal", detail: nil, icon: "apple.terminal", keys: nil) { store.openInTerminal(d) })
        }
        if !store.diffs.isEmpty { out.append(Action(id: "revert", title: "Revert all changes", detail: "\(store.diffs.count) files", icon: "arrow.uturn.backward", keys: nil) { store.revertAll() }) }
        out.append(Action(id: "keys", title: "Keyboard shortcuts", detail: nil, icon: "keyboard", keys: "⌘/") { store.shortcuts = true })
        out.append(Action(id: "settings", title: "Settings…", detail: nil, icon: "gearshape", keys: "⌘,") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) })
        for s in store.sessions.filter({ $0.parentID == nil }).sorted(by: { $0.updated > $1.updated }).prefix(40) {
            out.append(Action(id: "s-\(s.id)", title: s.title, detail: URL(fileURLWithPath: s.directory).lastPathComponent + " · " + ago(s.updated), icon: "bubble.left", keys: nil) { store.open(s.id) })
        }
        return out
    }
    var shown: [Action] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return Array(actions.prefix(14)) }
        return actions.filter { $0.title.lowercased().contains(q) || ($0.detail?.lowercased().contains(q) ?? false) }.prefix(14).map { $0 }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { store.palette = false }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Theme.dim)
                    TextField("Type a command, a model, a session…", text: $query)
                        .textFieldStyle(.plain).font(Theme.sans(15)).foregroundStyle(Theme.ink)
                        .focused($focused)
                        .onSubmit { run() }
                        .onChange(of: query) { _, _ in pick = 0 }
                        .onKeyPress(.upArrow) { pick = max(0, pick - 1); return .handled }
                        .onKeyPress(.downArrow) { pick = max(0, min(shown.count - 1, pick + 1)); return .handled }
                        .onKeyPress(.escape) { store.palette = false; return .handled }
                    Keys(keys: "esc")
                }
                .padding(.horizontal, 16).frame(height: 50)
                Rectangle().fill(Theme.line).frame(height: 1)
                let list = shown
                if list.isEmpty {
                    Text("Nothing matches").font(Theme.sans(12.5)).foregroundStyle(Theme.dim).padding(20)
                } else {
                    VStack(spacing: 1) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                            Button { store.palette = false; a.run() } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: a.icon).font(.system(size: 12)).foregroundStyle(i == pick ? Theme.ink2 : Theme.dim).frame(width: 16)
                                    Text(a.title).font(a.title.hasPrefix("/") ? Theme.mono(12.5) : Theme.sans(13)).foregroundStyle(Theme.ink).lineLimit(1)
                                    if let d = a.detail { Text(d).font(Theme.sans(12)).foregroundStyle(Theme.mute).lineLimit(1) }
                                    Spacer()
                                    if let k = a.keys { Keys(keys: k) }
                                }
                                .padding(.horizontal, 10).frame(height: 34)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(i == pick ? Theme.selected : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(Quiet())
                            .onHover { if $0 { pick = i } }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x232323)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line2))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
            .padding(.top, 110)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .onAppear { focused = true }
    }
    func run() {
        let list = shown
        guard list.indices.contains(pick) else { return } // ↓ with nothing matching used to leave pick at -1
        store.palette = false
        list[pick].run()
    }
}

/// every shortcut the desk answers to
struct ShortcutsSheet: View {
    @EnvironmentObject var store: Store
    let groups: [(String, [(String, String)])] = [
        ("Sessions", [("New session", "⌘N"), ("Open folder", "⌘O"), ("Commands", "⌘K"), ("Stop the agent", "esc"), ("Send", "↩"), ("New line", "⇧↩")]),
        ("Composer", [("Mention a file", "@"), ("Run a command", "/"), ("Accept a suggestion", "⇥"), ("Allow an approval", "↩"), ("Deny an approval", "esc")]),
        ("Permissions", [("Ask before edits", "⇧⌘1"), ("Edit automatically", "⇧⌘2"), ("Plan mode", "⇧⌘3"), ("Bypass permissions", "⇧⌘4")]),
        ("Panels", [("Toggle sidebar", "⌘\\"), ("Toggle side panel", "⌥⌘B"), ("Diff", "⇧⌘D"), ("Files", "⇧⌘E"), ("Terminal", "⌘J"), ("Settings", "⌘,"), ("This list", "⌘/")]),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard shortcuts").font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Button { store.shortcuts = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.mute) }.buttonStyle(Flat(pad: 6)).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).frame(height: 52)
            Rectangle().fill(Theme.line).frame(height: 1)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 22) {
                ForEach(groups, id: \.0) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(g.0).font(Theme.sans(11, .medium)).foregroundStyle(Theme.dim).padding(.bottom, 4)
                        ForEach(g.1, id: \.0) { k in
                            HStack {
                                Text(k.0).font(Theme.sans(12.5)).foregroundStyle(Theme.ink2)
                                Spacer()
                                Keys(keys: k.1)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 560)
        .background(Theme.raised)
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat, or fallback: CGFloat) -> CGFloat { self == 0 || !isFinite ? fallback : Swift.min(Swift.max(self, lo), hi) }
}
