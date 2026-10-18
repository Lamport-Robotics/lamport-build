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
            Brand().frame(height: 40).padding(.leading, 80)
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
            Account().padding(.horizontal, 8).padding(.top, 10)
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
            .font(Theme.sans(size * 0.46, .semibold)).foregroundStyle(Color(hex: 0x141414))
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
                    Text(u.pro ? "PRO" : "FREE").font(Theme.sans(9.5, .bold)).tracking(0.8)
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
            (Text("Lamport").foregroundStyle(Theme.ink) + Text(" Build").foregroundStyle(Theme.mute)).font(Theme.sans(13, .semibold))
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
