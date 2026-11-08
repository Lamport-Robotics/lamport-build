import SwiftUI
import UniformTypeIdentifiers

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
            Button { withAnimation(.easeOut(duration: 0.18)) { sidebar.toggle() } } label: { Image(systemName: "sidebar.left").font(.system(size: 13)).foregroundStyle(Theme.mute) }
                .buttonStyle(Flat(pad: 6)).help("Toggle sidebar  ⌘\\")
            Text(store.currentRow?.title ?? "New session").font(Theme.sans(13, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            if let dir = store.directory {
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 10.5))
                    Text(URL(fileURLWithPath: dir).lastPathComponent)
                    if let b = store.branch { Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).padding(.leading, 4); Text(b) }
                }
                .font(Theme.sans(11.5)).foregroundStyle(Theme.mute).lineLimit(1)
                .help(dir)
            }
            Spacer()
            if store.directory != nil {
                let t = store.diffTotals
                Button { toggle(.diff) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plusminus").font(.system(size: 11))
                        if t.add + t.del > 0 {
                            Text("+\(t.add)").foregroundStyle(Theme.green)
                            Text("−\(t.del)").foregroundStyle(Theme.red)
                        } else { Text("Diff") }
                    }
                    .font(Theme.sans(11.5, .medium)).monospacedDigit().foregroundStyle(active(.diff) ? Theme.ink : Theme.mute)
                }.buttonStyle(Flat(pad: 7)).help("Diff  ⇧⌘D")
                Button { toggle(.files) } label: {
                    Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(active(.files) ? Theme.ink : Theme.mute)
                }.buttonStyle(Flat(pad: 7)).help("Files  ⇧⌘E")
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
    static let ideas: [(String, String, String)] = [
        ("map", "Explain this codebase", "Walk me through how this project is put together: the entry points, the main modules and how they talk to each other."),
        ("ladybug", "Fix a failing test", "Run the test suite, find the failing tests and fix them. Show me the diff before you change anything else."),
        ("sparkles", "Add a feature", "I want to add "),
        ("doc.text.magnifyingglass", "Review my changes", "/review"),
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 0).frame(height: 110)
                if store.projects.isEmpty || (!store.onboarded && !store.signedIn) {
                    Welcome()
                } else {
                    Image("Mark").resizable().interpolation(.high).scaledToFit().frame(height: 40).opacity(0.92)
                    Text("What should we work on?").font(Theme.sans(24, .medium)).foregroundStyle(Theme.ink).padding(.top, 18)
                    Text("Describe a task in \(store.draftProject.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "your folder"). The agent reads, edits and runs the code, and asks before it changes anything.")
                        .font(Theme.sans(13)).foregroundStyle(Theme.mute).multilineTextAlignment(.center).frame(maxWidth: 440).padding(.top, 8)
                    VStack(alignment: .leading, spacing: 8) {
                        FolderPicker()
                        Composer(tall: true)
                    }
                    .frame(maxWidth: 680).padding(.top, 26)
                    HStack(spacing: 8) {
                        ForEach(Blank.ideas, id: \.1) { icon, title, text in
                            Button { store.draftText = text } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: icon).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                                    Text(title).font(Theme.sans(12)).foregroundStyle(Theme.ink2)
                                }
                                .padding(.horizontal, 11).frame(height: 28)
                                .background(Capsule().fill(Color.white.opacity(0.04)))
                                .overlay(Capsule().strokeBorder(Theme.line))
                            }.buttonStyle(Quiet())
                        }
                    }
                    .padding(.top, 16)
                    Recent().frame(maxWidth: 680).padding(.top, 36)
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

/// the first run: three short steps, each ticked as it happens
struct Welcome: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 0) {
            Image("Mark").resizable().interpolation(.high).scaledToFit().frame(height: 44).opacity(0.92)
            Text("Lamport Build").font(Theme.sans(26, .medium)).foregroundStyle(Theme.ink).padding(.top, 18)
            Text("A coding agent that works in a folder on this Mac. It reads, edits and runs the code there, and shows every change before it lands.")
                .font(Theme.sans(13.5)).foregroundStyle(Theme.mute).multilineTextAlignment(.center).frame(maxWidth: 440).padding(.top, 8).lineSpacing(3)
            VStack(spacing: 0) {
                Step(n: 1, done: store.signedIn, title: "Sign in with Lamport", detail: store.signedIn ? "Signed in as \(store.who ?? "a Lamport member")" : "Free members get a daily allowance of turns. No provider keys on this Mac.") {
                    if !store.signedIn {
                        Button(store.signingIn ? "Waiting for the browser…" : "Sign in") { store.signingIn ? store.cancelSignIn() : store.signIn() }.buttonStyle(Primary())
                    }
                }
                Rectangle().fill(Theme.line).frame(height: 1)
                Step(n: 2, done: !store.projects.isEmpty, title: "Open a folder", detail: store.projects.first.map { "Working in \($0.name)" } ?? "A git repository works best: the diff panel follows every edit.") {
                    Button(store.projects.isEmpty ? "Open folder…" : "Another folder…") { store.pickFolder() }.buttonStyle(store.projects.isEmpty && store.signedIn ? AnyButtonStyle(Primary()) : AnyButtonStyle(Secondary()))
                }
                Rectangle().fill(Theme.line).frame(height: 1)
                Step(n: 3, done: false, title: "Describe the task", detail: "Ask a question, paste an error or name the feature. The agent asks before it edits or runs anything.") {
                    if !store.projects.isEmpty { Button("Start") { store.onboarded = true }.buttonStyle(store.signedIn ? AnyButtonStyle(Primary()) : AnyButtonStyle(Secondary())) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
            .frame(maxWidth: 560).padding(.top, 30)
            if let e = store.authError { Text(e).font(Theme.sans(12)).foregroundStyle(Theme.red).padding(.top, 12) }
        }
    }
}

struct Step<Trailing: View>: View {
    var n: Int; var done: Bool; var title: String; var detail: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(done ? Theme.green.opacity(0.15) : Color.white.opacity(0.06)).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.green) }
                else { Text("\(n)").font(Theme.sans(12, .medium)).foregroundStyle(Theme.ink2) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.sans(13.5, .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.sans(12)).foregroundStyle(Theme.mute).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
    }
}

struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// the last few sessions in the folder, under the composer
struct Recent: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let rows = store.draftProject.map { store.rows(for: Project(path: $0)) }?.prefix(5) ?? []
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent").font(Theme.sans(11, .medium)).foregroundStyle(Theme.dim).padding(.leading, 10).padding(.bottom, 6)
                ForEach(Array(rows)) { r in
                    Button { store.open(r.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bubble.left").font(.system(size: 11)).foregroundStyle(Theme.dim)
                            Text(r.title).font(Theme.sans(12.5)).foregroundStyle(Theme.ink2).lineLimit(1)
                            Spacer()
                            Text(ago(r.updated)).font(Theme.sans(11)).foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, 10).frame(height: 30)
                    }.buttonStyle(Flat(pad: 0))
                }
            }
        }
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
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(list) { m in
                        switch m.role {
                        case .user: UserBubble(text: m.text)
                        case .assistant: AssistantView(message: m)
                        case .notice: Notice(text: m.text)
                        }
                    }
                    if store.isBusy { Working(tools: list.last?.tools ?? 0) }
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

struct Notice: View {
    var text: String
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Text(text).font(Theme.sans(11.5)).foregroundStyle(Theme.dim).fixedSize()
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .padding(.vertical, 2)
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
                .contextMenu { Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } }
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
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(done ? "Thought" : "Thinking").font(Theme.sans(12.5)).foregroundStyle(Theme.mute)
                        .modifier(Shimmer(active: !done))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim).rotationEffect(.degrees(open ? 90 : 0))
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
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    StatusDot(status: call.status)
                    Image(systemName: call.icon).font(.system(size: 10.5)).foregroundStyle(Theme.dim).frame(width: 14)
                    Text(call.label).font(Theme.sans(12.5, .medium)).foregroundStyle(Theme.ink2)
                    Text(call.subject(in: store.directory)).font(Theme.mono(11.5)).foregroundStyle(Theme.mute).lineLimit(1).truncationMode(.middle)
                    if let e = edits, call.status == .done {
                        Text("+\(e.new.count)").font(Theme.mono(10.5)).foregroundStyle(Theme.green)
                        if !e.old.isEmpty { Text("−\(e.old.count)").font(Theme.mono(10.5)).foregroundStyle(Theme.red) }
                    }
                    Spacer(minLength: 0)
                    if hasDetail { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim).rotationEffect(.degrees(open ? 90 : 0)) }
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
    var path: String { ((call.input["filePath"] ?? call.input["file_path"] ?? call.input["path"]) as? String) ?? "" }
    @ViewBuilder var detail: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if let e = edits {
                    let lang = fileKind(path)
                    ForEach(Array(e.old.prefix(200).enumerated()), id: \.offset) { DiffLine(kind: .del, text: $0.element, lang: lang) }
                    ForEach(Array(e.new.prefix(200).enumerated()), id: \.offset) { DiffLine(kind: .add, text: $0.element, lang: lang) }
                } else {
                    Text(call.output.count > 20_000 ? String(call.output.prefix(20_000)) + "\n…" : call.output)
                        .font(Theme.mono(11.5)).foregroundStyle(call.status == .failed ? Theme.red : Theme.ink2).lineSpacing(2)
                        .textSelection(.enabled).padding(10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 280)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
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
    var tools: Int
    @State private var start = Date()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 8) {
                Text("Working").font(Theme.sans(12.5)).foregroundStyle(Theme.mute).modifier(Shimmer(active: true))
                let s = Int(ctx.date.timeIntervalSince(start))
                Text("\(s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s")\(tools > 0 ? " · \(tools) tool call\(tools == 1 ? "" : "s")" : "") · esc to stop").font(Theme.sans(11.5)).foregroundStyle(Theme.dim).monospacedDigit()
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
    var icon: String {
        switch ask.action {
        case "shell", "bash": "terminal"
        case "edit", "write", "patch": "pencil.line"
        case "read": "doc.text"
        case "webfetch", "websearch": "globe"
        default: "hand.raised"
        }
    }
    /// "Always allow npm *" when the engine offers a pattern, a plain "for this session" when it is everything
    var always: String {
        let pats = ask.save.filter { $0 != "*" }
        return pats.isEmpty ? "Always allow in this session" : "Always allow \(pats.joined(separator: ", "))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11.5)).foregroundStyle(Theme.amber)
                Text(title).font(Theme.sans(13, .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Keys(keys: "↩").help("Allow")
            }
            if !ask.resources.isEmpty {
                let lang = ask.action == "shell" || ask.action == "bash" ? "sh" : fileKind(ask.resources[0])
                Text(Highlighter.attributed(ask.resources.map { Store.short($0, root: store.directory) }.joined(separator: "\n"), lang: lang, font: Theme.mono(12)))
                    .textSelection(.enabled).lineLimit(8)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
            }
            HStack(spacing: 8) {
                Button("Allow") { store.reply(ask, "once") }.buttonStyle(Primary()).keyboardShortcut(.return, modifiers: [])
                Button(always) { store.reply(ask, "always") }.buttonStyle(Secondary()).lineLimit(1)
                Spacer()
                Button("Deny") { store.reply(ask, "reject") }.buttonStyle(Secondary()).keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.amber.opacity(0.28)))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: composer

/// one row the composer offers while you type @ or /
struct Suggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    /// what replaces the token being typed
    let insert: String
}

struct Composer: View {
    @EnvironmentObject var store: Store
    var tall = false
    @State private var text = ""
    @State private var suggestions: [Suggestion] = []
    @State private var pick = 0
    @State private var lookup: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !suggestions.isEmpty {
                SuggestionList(items: suggestions, pick: pick) { accept($0) }
                    .padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField(store.current == nil ? "Describe a task, ask about the code, paste an error…" : "Reply…  @ for files, / for commands", text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(Theme.sans(13.5)).foregroundStyle(Theme.ink)
                    .lineLimit(tall ? 3...12 : 1...12)
                    .focused($focused)
                    .onSubmit { if !suggestions.isEmpty { accept(suggestions[min(pick, suggestions.count - 1)]) } else { submit() } }
                    .onChange(of: text) { _, _ in refreshSuggestions() }
                    .onKeyPress(.upArrow) { guard !suggestions.isEmpty else { return .ignored }; pick = (pick - 1 + suggestions.count) % suggestions.count; return .handled }
                    .onKeyPress(.downArrow) { guard !suggestions.isEmpty else { return .ignored }; pick = (pick + 1) % suggestions.count; return .handled }
                    .onKeyPress(.tab) { guard !suggestions.isEmpty else { return .ignored }; accept(suggestions[min(pick, suggestions.count - 1)]); return .handled }
                    .onKeyPress(.escape) { guard !suggestions.isEmpty else { return .ignored }; suggestions = []; return .handled }
                    .padding(.top, 2)
                HStack(spacing: 4) {
                    Menu {
                        ForEach(Mode.allCases) { m in Button { store.mode = m } label: { if m == store.mode { Label(m.title, systemImage: "checkmark") } else { Text(m.title) } } }
                    } label: {
                        HStack(spacing: 5) { Image(systemName: store.mode.icon).font(.system(size: 10.5)); Text(store.mode.short) }
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
                        }.buttonStyle(Quiet()).disabled(!canSend).help("Send  ↩")
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 9)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? Theme.line2 : Theme.line))
        }
        .onAppear { focused = true }
        .onChange(of: store.draftText) { _, d in
            guard let d else { return }
            text = d; store.draftText = nil; focused = true
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + "@" + Store.short(url.path, root: store.directory) + " " }
                }
            }
            return true
        }
    }
    var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (store.current != nil || store.draftProject != nil) }
    func submit() {
        guard canSend, !store.isBusy else { return }
        let t = text; text = ""; suggestions = []
        Task { await store.send(t) }
    }

    /// the token under the caret: "@src/ap" or "/rev", taken as the last word of the text
    var token: (prefix: Character, query: String)? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last, let c = last.first, c == "@" || c == "/" else { return nil }
        if c == "/", !text.hasPrefix("/") { return nil }
        if last.contains("\n") { return nil }
        return (c, String(last.dropFirst()))
    }
    func refreshSuggestions() {
        lookup?.cancel()
        guard let tok = token else { suggestions = []; return }
        pick = 0
        if tok.prefix == "/" {
            let q = tok.query.lowercased()
            suggestions = store.commands.filter { q.isEmpty || $0.name.lowercased().contains(q) }.prefix(8).map { Suggestion(id: $0.name, title: "/" + $0.name, detail: $0.description, icon: "command", insert: "/" + $0.name + " ") }
            return
        }
        lookup = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let files = await store.findFiles(tok.query)
            guard !Task.isCancelled else { return }
            suggestions = files.map { Suggestion(id: $0, title: URL(fileURLWithPath: $0).lastPathComponent, detail: $0, icon: fileIcon($0), insert: "@" + $0 + " ") }
        }
    }
    func accept(_ s: Suggestion) {
        var parts = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !parts.isEmpty { parts.removeLast() }
        text = (parts + [s.insert]).joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
        suggestions = []
    }
}

struct SuggestionList: View {
    var items: [Suggestion]; var pick: Int; var choose: (Suggestion) -> Void
    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                Button { choose(s) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: s.icon).font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: 14)
                        Text(s.title).font(s.title.hasPrefix("/") ? Theme.mono(12) : Theme.sans(12.5)).foregroundStyle(Theme.ink)
                        Text(s.detail).font(s.title.hasPrefix("/") ? Theme.sans(12) : Theme.mono(11)).foregroundStyle(Theme.mute).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if i == pick { Keys(keys: "↩") }
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(i == pick ? Theme.selected : .clear))
                    .contentShape(Rectangle())
                }.buttonStyle(Quiet())
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line2))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
