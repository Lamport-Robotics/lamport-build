import SwiftUI

/// the middle of the window: the header, the flow of the session, the approval card and the composer
struct Conversation: View {
    @EnvironmentObject var store: Store
    @Binding var sidebar: Bool
    var body: some View {
        VStack(spacing: 0) {
            Header(sidebar: $sidebar)
            if store.current == nil {
                Blank()
            } else {
                Flow()
                VStack(spacing: 10) {
                    ForEach(store.currentAsks) { AskCard(ask: $0) }
                    Composer()
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 24).padding(.bottom, 18)
            }
        }
    }
}

struct Header: View {
    @EnvironmentObject var store: Store
    @Binding var sidebar: Bool
    var body: some View {
        HStack(spacing: 10) {
            if !sidebar { Color.clear.frame(width: 64) }
            Button { sidebar.toggle() } label: { Image(systemName: "sidebar.left").font(.system(size: 13)).foregroundStyle(Theme.mute) }
                .buttonStyle(Flat(pad: 6)).help("Toggle sidebar")
            Text(store.currentRow?.title ?? "New session").font(Theme.sans(13, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            if let dir = store.directory {
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 10.5))
                    Text(URL(fileURLWithPath: dir).lastPathComponent)
                    if let b = store.branch { Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).padding(.leading, 4); Text(b) }
                }
                .font(Theme.sans(11.5)).foregroundStyle(Theme.mute).lineLimit(1)
            }
            Spacer()
            if store.directory != nil {
                Button { toggle(.diff) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plusminus").font(.system(size: 11))
                        let t = store.diffTotals
                        if t.add + t.del > 0 {
                            Text("+\(t.add)").foregroundStyle(Theme.green)
                            Text("−\(t.del)").foregroundStyle(Theme.red)
                        } else { Text("Diff") }
                    }
                    .font(Theme.mono(11.5)).foregroundStyle(active(.diff) ? Theme.ink : Theme.mute)
                }.buttonStyle(Flat(pad: 7)).help("Diff  ⇧⌘D")
                Button { toggle(.terminal) } label: {
                    Image(systemName: "terminal").font(.system(size: 12)).foregroundStyle(active(.terminal) ? Theme.ink : Theme.mute)
                }.buttonStyle(Flat(pad: 7)).help("Terminal  ⌘J")
            }
        }
        .padding(.leading, 12).padding(.trailing, 12)
        .frame(height: 44)
        .padding(.top, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
    func active(_ t: SideTab) -> Bool { store.sideOpen && store.sideTab == t }
    func toggle(_ t: SideTab) {
        if active(t) { store.sideOpen = false } else { store.sideTab = t; store.sideOpen = true }
    }
}

// MARK: a new session, before its first message

struct Blank: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            if store.projects.isEmpty {
                VStack(spacing: 14) {
                    Image("Mark").resizable().interpolation(.high).scaledToFit().frame(height: 38).opacity(0.9)
                    Text("Open a folder to begin").font(Theme.sans(22, .medium)).foregroundStyle(Theme.ink)
                    Text("Lamport Build reads, edits and runs the code in a folder on this Mac. Nothing leaves it except what the model needs to see.")
                        .font(Theme.sans(13)).foregroundStyle(Theme.mute).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Open folder…") { store.pickFolder() }.buttonStyle(Primary()).padding(.top, 6)
                }
            } else {
                Image("Mark").resizable().interpolation(.high).scaledToFit().frame(height: 38).opacity(0.9).padding(.bottom, 2)
                Text("What should we work on?").font(Theme.sans(22, .medium)).foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 8) {
                    FolderPicker()
                    Composer(tall: true)
                }
                .frame(maxWidth: 680)
            }
            Spacer(); Spacer()
        }
        .padding(.horizontal, 32)
    }
}

struct FolderPicker: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Menu {
            ForEach(store.projects) { p in Button(p.name) { store.draftProject = p.path; Task { await store.refreshSide() } } }
            Divider()
            Button("Open folder…") { store.pickFolder() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 11))
                Text(store.draftProject.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose a folder")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(Theme.sans(12)).foregroundStyle(Theme.ink2)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(.leading, 4)
    }
}

// MARK: the flow

struct Flow: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let list = store.currentMessages
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(list) { m in
                        switch m.role {
                        case .user: UserBubble(text: m.text)
                        case .assistant: AssistantView(message: m)
                        case .notice: Text(m.text).font(Theme.sans(12)).foregroundStyle(Theme.mute).frame(maxWidth: .infinity)
                        }
                    }
                    if store.isBusy { Working() }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: 712, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: store.current) { _, _ in DispatchQueue.main.async { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: fingerprint(list)) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }
    /// changes whenever something new streams in, so the view follows the bottom
    func fingerprint(_ list: [Message]) -> Int {
        var h = Hasher()
        h.combine(list.count)
        if let last = list.last {
            h.combine(last.blocks.count)
            if case .text(_, let t) = last.blocks.last { h.combine(t.count) }
            if case .thinking(_, let t, _) = last.blocks.last { h.combine(t.count) }
        }
        return h.finalize()
    }
}

struct UserBubble: View {
    var text: String
    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(text).font(Theme.sans(13.5)).foregroundStyle(Theme.ink).lineSpacing(3).textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
        }
    }
}

struct AssistantView: View {
    var message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.blocks) { b in
                switch b {
                case .thinking(_, let text, let done): Thinking(text: text, done: done)
                case .text(_, let text): Markdown(text: text)
                case .tool(let t): ToolView(call: t)
                }
            }
        }
    }
}

struct Thinking: View {
    var text: String; var done: Bool
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Text(done ? "Thought" : "Thinking").font(Theme.sans(12.5)).foregroundStyle(Theme.mute)
                        .modifier(Shimmer(active: !done))
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim)
                }
            }.buttonStyle(Quiet())
            if open, !text.isEmpty {
                Text(text).font(Theme.sans(12.5)).foregroundStyle(Theme.mute).lineSpacing(3).textSelection(.enabled)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.line2).frame(width: 2) }
            }
        }
    }
}

struct ToolView: View {
    @EnvironmentObject var store: Store
    var call: ToolCall
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    StatusDot(status: call.status)
                    Text(call.label).font(Theme.sans(12.5, .medium)).foregroundStyle(Theme.ink2)
                    Text(call.subject(in: store.directory)).font(Theme.mono(12)).foregroundStyle(Theme.mute).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if hasDetail { Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim) }
                }
            }.buttonStyle(Quiet())
            if open, hasDetail { detail }
        }
    }
    var hasDetail: Bool { !call.output.isEmpty || edits != nil }
    /// the lines a write or an edit puts on disk, as removed and added lines
    var edits: (old: [String], new: [String])? {
        let i = call.input
        if let o = (i["oldString"] ?? i["old_string"]) as? String, let n = (i["newString"] ?? i["new_string"]) as? String { return (o.components(separatedBy: "\n"), n.components(separatedBy: "\n")) }
        if call.name == "write", let c = i["content"] as? String { return ([], c.components(separatedBy: "\n")) }
        return nil
    }
    @ViewBuilder var detail: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if let e = edits {
                    ForEach(Array(e.old.prefix(200).enumerated()), id: \.offset) { DiffLine(text: "-" + $0.element) }
                    ForEach(Array(e.new.prefix(200).enumerated()), id: \.offset) { DiffLine(text: "+" + $0.element) }
                } else {
                    Text(call.output.count > 20_000 ? String(call.output.prefix(20_000)) + "\n…" : call.output)
                        .font(Theme.mono(11.5)).foregroundStyle(call.status == .failed ? Theme.red : Theme.ink2).lineSpacing(2)
                        .textSelection(.enabled).padding(10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 260)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
        .padding(.leading, 18)
    }
}

struct StatusDot: View {
    var status: ToolCall.Status
    var body: some View {
        Group {
            switch status {
            case .pending, .running: ProgressView().controlSize(.mini).scaleEffect(0.65)
            case .done: Circle().fill(Theme.green).frame(width: 6, height: 6)
            case .failed: Circle().fill(Theme.red).frame(width: 6, height: 6)
            }
        }
        .frame(width: 10, height: 10)
    }
}

struct Working: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 8) {
                Text("Working").font(Theme.sans(12.5)).foregroundStyle(Theme.mute).modifier(Shimmer(active: true))
                Text("\(Int(ctx.date.timeIntervalSince(start)))s · esc to stop").font(Theme.sans(11.5)).foregroundStyle(Theme.dim)
            }
        }
    }
}

/// a soft highlight sweeping over text that is still in progress
struct Shimmer: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        if !active { content } else {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                content.overlay(
                    LinearGradient(colors: [.clear, Color.white.opacity(0.75), .clear], startPoint: UnitPoint(x: t * 2 - 0.6, y: 0.5), endPoint: UnitPoint(x: t * 2 - 0.1, y: 0.5))
                        .mask(content)
                )
            }
        }
    }
}

// MARK: approvals

struct AskCard: View {
    @EnvironmentObject var store: Store
    var ask: PermissionAsk
    var title: String {
        switch ask.action {
        case "shell", "bash": "Run this command?"
        case "edit", "write", "patch": "Make this edit?"
        case "read": "Read this file?"
        case "webfetch", "websearch": "Go to the web?"
        default: "Allow \(ask.action)?"
        }
    }
    /// "Always allow npm *" when the engine offers a pattern, a plain "for this session" when it is everything
    var always: String {
        let pats = ask.save.filter { $0 != "*" }
        return pats.isEmpty ? "Always allow in this session" : "Always allow \(pats.joined(separator: ", "))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Theme.amber).frame(width: 6, height: 6)
                Text(title).font(Theme.sans(13, .medium)).foregroundStyle(Theme.ink)
            }
            if !ask.resources.isEmpty {
                Text(ask.resources.map { Store.short($0, root: store.directory) }.joined(separator: "\n")).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
                    .textSelection(.enabled).lineLimit(8)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.28)))
            }
            HStack(spacing: 8) {
                Button("Allow") { store.reply(ask, "once") }.buttonStyle(Primary()).keyboardShortcut(.return, modifiers: [])
                Button(always) { store.reply(ask, "always") }.buttonStyle(Secondary()).lineLimit(1)
                Spacer()
                Button("Deny") { store.reply(ask, "reject") }.buttonStyle(Secondary())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.amber.opacity(0.28)))
    }
}

// MARK: composer

struct Composer: View {
    @EnvironmentObject var store: Store
    var tall = false
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(store.current == nil ? "Describe a task, ask about the code, paste an error…" : "Reply…", text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(Theme.sans(13.5)).foregroundStyle(Theme.ink)
                .lineLimit(tall ? 3...12 : 1...12)
                .focused($focused)
                .onSubmit(submit)
                .padding(.top, 2)
            HStack(spacing: 4) {
                Menu {
                    ForEach(Mode.allCases) { m in Button { store.mode = m } label: { if m == store.mode { Label(m.title, systemImage: "checkmark") } else { Text(m.title) } } }
                } label: {
                    HStack(spacing: 5) { Image(systemName: icon(store.mode)).font(.system(size: 10.5)); Text(store.mode.short) }
                        .font(Theme.sans(12)).foregroundStyle(store.mode == .bypass ? Theme.amber : Theme.mute)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Permissions  ⇧⌘1–4")
                Menu {
                    let lamport = store.models.filter(\.isLamport), local = store.models.filter(\.isLocal)
                    if !lamport.isEmpty {
                        Section("Lamport") {
                            ForEach(lamport) { m in
                                if m.locked { Button("\(m.name)  ·  Pro") {}.disabled(true) }
                                else { Button { store.choose(m) } label: { if m == store.model { Label(m.name, systemImage: "checkmark") } else { Text(m.name) } } }
                            }
                        }
                    } else if !store.signedIn {
                        Button("Sign in to use Lamport's models") { store.signIn() }
                    }
                    if !local.isEmpty {
                        Section("On this Mac") {
                            ForEach(local) { m in Button { store.choose(m) } label: { if m == store.model { Label(m.name, systemImage: "checkmark") } else { Text(m.name) } } }
                        }
                    }
                } label: {
                    HStack(spacing: 4) { Text(store.model?.name ?? "Model"); Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .semibold)) }
                        .font(Theme.sans(12)).foregroundStyle(Theme.mute)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.leading, 10)
                Spacer()
                if store.isBusy {
                    Button(action: store.stop) {
                        Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(Color(hex: 0x141414))
                            .frame(width: 26, height: 26).background(Circle().fill(Theme.ink))
                    }.buttonStyle(Quiet()).keyboardShortcut(.escape, modifiers: []).help("Stop  esc")
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.up").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color(hex: 0x141414))
                            .frame(width: 26, height: 26).background(Circle().fill(canSend ? Theme.ink : Theme.dim))
                    }.buttonStyle(Quiet()).disabled(!canSend)
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? Theme.line2 : Theme.line))
        .onAppear { focused = true }
    }
    var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (store.current != nil || store.draftProject != nil) }
    func submit() {
        guard canSend, !store.isBusy else { return }
        let t = text; text = ""
        Task { await store.send(t) }
    }
    func icon(_ m: Mode) -> String {
        switch m { case .ask: "hand.raised"; case .edits: "pencil"; case .plan: "list.bullet.clipboard"; case .bypass: "bolt" }
    }
}
