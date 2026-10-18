import SwiftUI
import AppKit

// MARK: what the desk shows

struct Project: Identifiable, Hashable {
    let path: String
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct SessionRow: Identifiable, Equatable {
    let id: String
    var title: String
    var directory: String
    var updated: Date
    var parentID: String?
}

struct ToolCall: Identifiable {
    enum Status { case pending, running, done, failed }
    let id: String
    var name: String
    var input: [String: Any] = [:]
    var status: Status = .pending
    var output = ""

    /// the one line that says what the call touches: the command, the path, the pattern; paths relative to the folder
    func subject(in root: String?) -> String {
        for k in ["command", "path", "filePath", "file_path", "pattern", "query", "url", "description", "prompt"] {
            if let s = input[k] as? String, !s.isEmpty { return k.lowercased().contains("path") ? Store.short(s, root: root) : s }
        }
        return ""
    }
    var label: String {
        switch name {
        case "shell", "bash": "Shell"
        case "write": "Write"
        case "edit", "patch", "multiedit": "Edit"
        case "read": "Read"
        case "grep": "Search"
        case "glob", "list", "ls": "List"
        case "webfetch", "fetch": "Fetch"
        case "websearch": "Web"
        case "task": "Agent"
        case "todowrite", "todoread": "Todo"
        default: name.prefix(1).uppercased() + name.dropFirst()
        }
    }
}

enum Block: Identifiable {
    case thinking(id: String, text: String, done: Bool)
    case text(id: String, text: String)
    case tool(ToolCall)
    var id: String {
        switch self { case .thinking(let id, _, _), .text(let id, _): id; case .tool(let t): t.id }
    }
}

struct Message: Identifiable {
    enum Role { case user, assistant, notice }
    let id: String
    var role: Role
    var text = ""
    var blocks: [Block] = []
    var at = Date()
}

struct PermissionAsk: Identifiable {
    let id: String
    let sessionID: String
    let action: String
    let resources: [String]
    let save: [String]
}

struct FileDiff: Identifiable {
    var id: String { file }
    let file: String
    let patch: String
    let additions: Int
    let deletions: Int
    let status: String
}

struct ModelChoice: Identifiable, Hashable {
    let id: String
    let providerID: String
    let name: String
    /// shown but not usable on this plan (Lamport SI without Pro)
    var locked = false
    var key: String { providerID + "/" + id }
    var isLamport: Bool { providerID == Store.provider }
    /// models served by something running on this Mac
    var isLocal: Bool { Store.localProviders.contains(providerID) }
}

/// today's allowance on lamport.si, as the proxy counts it
struct Usage: Equatable {
    var pro: Bool
    var turns: Int
    var turnLimit: Int
    var tokens: Int
    var tokenLimit: Int
    var turnsLeft: Int { max(0, turnLimit - turns) }
}

/// how much the agent may do without asking: the same four modes as the Claude Code desktop
enum Mode: String, CaseIterable, Identifiable {
    case ask, edits, plan, bypass
    var id: String { rawValue }
    var title: String {
        switch self { case .ask: "Ask before edits"; case .edits: "Edit automatically"; case .plan: "Plan mode"; case .bypass: "Bypass permissions" }
    }
    var short: String {
        switch self { case .ask: "Ask"; case .edits: "Auto-edit"; case .plan: "Plan"; case .bypass: "Bypass" }
    }
    var agent: String { self == .plan ? "plan" : "build" }
    var rules: [[String: String]] {
        let edits = ["edit", "write", "patch"].map { ["action": $0, "resource": "*", "effect": "ask"] }
        let shell = [["action": "shell", "resource": "*", "effect": "ask"]]
        switch self {
        case .ask, .plan: return edits + shell
        case .edits: return shell
        case .bypass: return [["action": "*", "resource": "*", "effect": "allow"]]
        }
    }
}

enum SideTab: String { case diff, terminal }

// MARK: the desk's state, fed by the engine's event stream

@MainActor
final class Store: ObservableObject {
    let engine = Engine()

    @Published var projects: [Project] = []
    @Published var sessions: [SessionRow] = []
    @Published var current: String?
    /// the folder a new session will open in, before its first message creates it
    @Published var draftProject: String?
    @Published var messages: [String: [Message]] = [:]
    @Published var busy: Set<String> = []
    @Published var asks: [PermissionAsk] = []
    @Published var models: [ModelChoice] = []
    @Published var model: ModelChoice?
    @Published var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .ask { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode"); Task { await applyMode() } } }
    @Published var diffs: [FileDiff] = []
    @Published var diffNote: String?
    @Published var branch: String?
    @Published var sideOpen = UserDefaults.standard.object(forKey: "sideOpen") as? Bool ?? true { didSet { UserDefaults.standard.set(sideOpen, forKey: "sideOpen") } }
    @Published var sideTab: SideTab = .diff
    @Published var search = ""
    @Published var toast: String?
    @Published var cost: [String: Double] = [:]
    @Published var signedIn = API.token != nil
    @Published var signingIn = false
    @Published var who: String? = UserDefaults.standard.string(forKey: API.whoKey)
    @Published var authError: String?
    @Published var usage: Usage?

    private var loaded: Set<String> = []

    init() {
        projects = (UserDefaults.standard.stringArray(forKey: "projects") ?? []).filter { FileManager.default.fileExists(atPath: $0) }.map(Project.init)
        if let i = CommandLine.arguments.firstIndex(of: "--folder"), i + 1 < CommandLine.arguments.count { addProject(CommandLine.arguments[i + 1]) }
    }

    // MARK: derived

    var directory: String? {
        if let c = current, let s = sessions.first(where: { $0.id == c }) { return s.directory }
        return draftProject
    }
    var currentRow: SessionRow? { sessions.first { $0.id == current } }
    var currentMessages: [Message] { current.flatMap { messages[$0] } ?? [] }
    var currentAsks: [PermissionAsk] { asks.filter { $0.sessionID == current } }
    var isBusy: Bool { current.map { busy.contains($0) } ?? false }
    func rows(for p: Project) -> [SessionRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return sessions.filter { $0.directory == p.path && $0.parentID == nil && (q.isEmpty || $0.title.lowercased().contains(q)) }.sorted { $0.updated > $1.updated }
    }
    nonisolated static func short(_ path: String, root: String? = nil) -> String {
        if let root, path == root { return "." }
        if let root, path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: start up

    func boot() async {
        await engine.start()
        guard engine.state == .ready else { return }
        Task { await listen() }
        await connectLamport()
        await loadModels()
        await loadSessions()
        if current == nil, draftProject == nil { draftProject = projects.first?.path }
        await refreshSide()
        if let i = CommandLine.arguments.firstIndex(of: "--prompt"), i + 1 < CommandLine.arguments.count { await send(CommandLine.arguments[i + 1]) }
    }

    func loadModels() async {
        let list = (try? await engine.data("/api/model") as? [[String: Any]]) ?? []
        models = list.filter { ($0["enabled"] as? Bool) != false && ($0["status"] as? String) != "deprecated" }.compactMap {
            guard let id = $0["id"] as? String, let p = $0["providerID"] as? String else { return nil }
            return ModelChoice(id: id, providerID: p, name: $0["name"] as? String ?? id)
        }
        // the picker offers lamport's models (they exist only while signed in) and models running on this Mac;
        // anything else the engine knows about stays out of sight
        let lamport = models.filter(\.isLamport)
        models = lamport + lockedLamport(besides: lamport) + models.filter(\.isLocal)
        // a model you picked yourself sticks; otherwise lamport's first, else the first local one
        if let saved = UserDefaults.standard.string(forKey: "model"), let m = models.first(where: { $0.key == saved && !$0.locked }) { model = m; return }
        model = lamport.first ?? models.first { $0.isLocal }
        Log.write("model \(model?.key ?? "engine default") of \(models.count)")
    }

    func loadSessions() async {
        let list = (try? await engine.data("/api/session", query: [("limit", "300")]) as? [[String: Any]]) ?? []
        sessions = list.compactMap(Store.row)
        for dir in Set(sessions.map(\.directory)) where !projects.contains(where: { $0.path == dir }) && FileManager.default.fileExists(atPath: dir) { projects.append(Project(path: dir)) }
        saveProjects()
    }

    nonisolated static func row(_ d: [String: Any]) -> SessionRow? {
        guard let id = (d["id"] ?? d["sessionID"]) as? String else { return nil }
        let loc = (d["location"] as? [String: Any])?["directory"] as? String ?? ""
        let time = d["time"] as? [String: Any]
        let updated = (time?["updated"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        return SessionRow(id: id, title: (d["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "New session", directory: loc, updated: updated, parentID: d["parentID"] as? String)
    }

    // MARK: projects and sessions

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Open"
        guard p.runModal() == .OK, let u = p.url else { return }
        addProject(u.path)
        newSession(in: u.path)
    }

    func addProject(_ path: String) {
        if !projects.contains(where: { $0.path == path }) { projects.insert(Project(path: path), at: 0); saveProjects() }
    }
    func removeProject(_ p: Project) {
        projects.removeAll { $0 == p }; saveProjects()
        if directory == p.path { current = nil; draftProject = projects.first?.path }
    }
    private func saveProjects() { UserDefaults.standard.set(projects.map(\.path), forKey: "projects") }

    func newSession(in path: String? = nil) {
        current = nil
        draftProject = path ?? directory ?? projects.first?.path
        Task { await refreshSide() }
    }

    func open(_ id: String) {
        current = id
        draftProject = nil
        Task {
            if !loaded.contains(id) { await loadMessages(id) }
            await refreshSide()
        }
    }

    func delete(_ row: SessionRow) {
        Task {
            _ = try? await engine.call("/api/session/\(row.id)", method: "DELETE")
            sessions.removeAll { $0.id == row.id }
            messages[row.id] = nil
            if current == row.id { newSession(in: row.directory) }
        }
    }

    func rename(_ row: SessionRow, to title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if let i = sessions.firstIndex(where: { $0.id == row.id }) { sessions[i].title = t }
        Task { _ = try? await engine.call("/api/session/\(row.id)", method: "PATCH", json: ["title": t]) }
    }

    func loadMessages(_ id: String) async {
        guard let list = try? await engine.data("/api/session/\(id)/message", query: [("limit", "400")]) as? [[String: Any]] else { return }
        let sorted = list.sorted { (($0["time"] as? [String: Any])?["created"] as? Double ?? 0) < (($1["time"] as? [String: Any])?["created"] as? Double ?? 0) }
        var out: [Message] = []
        for m in sorted {
            let at = ((m["time"] as? [String: Any])?["created"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            guard let mid = m["id"] as? String else { continue }
            switch m["type"] as? String {
            case "user":
                out.append(Message(id: mid, role: .user, text: m["text"] as? String ?? "", at: at))
            case "assistant":
                var msg = Message(id: mid, role: .assistant, at: at)
                for (i, c) in ((m["content"] as? [[String: Any]]) ?? []).enumerated() {
                    switch c["type"] as? String {
                    case "reasoning": msg.blocks.append(.thinking(id: "\(mid)-r\(i)", text: c["text"] as? String ?? "", done: true))
                    case "text": msg.blocks.append(.text(id: "\(mid)-t\(i)", text: c["text"] as? String ?? ""))
                    case "tool":
                        let st = c["state"] as? [String: Any] ?? [:]
                        var t = ToolCall(id: c["id"] as? String ?? "\(mid)-\(i)", name: c["name"] as? String ?? "tool")
                        t.input = st["input"] as? [String: Any] ?? [:]
                        switch st["status"] as? String {
                        case "completed": t.status = .done
                        case "error": t.status = .failed
                        case "running": t.status = .running
                        default: t.status = .pending
                        }
                        t.output = Store.text(st["content"]) + Store.errorText(st["error"])
                        msg.blocks.append(.tool(t))
                    default: break
                    }
                }
                out.append(msg)
            case "idle":
                if m["outcome"] as? String == "failed" { out.append(Message(id: mid, role: .notice, text: Store.errorText(m["error"]).nilIfEmpty ?? "The run failed.", at: at)) }
                if m["outcome"] as? String == "interrupted" { out.append(Message(id: mid, role: .notice, text: "Stopped.", at: at)) }
            default: break
            }
        }
        messages[id] = out
        loaded.insert(id)
        if let pending = try? await engine.data("/api/session/\(id)/permission") as? [[String: Any]] { for p in pending { addAsk(p) } }
    }

    // MARK: talking to the agent

    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, engine.state == .ready else { return }
        // models run through lamport.si on the member's own token, so a session starts signed in
        guard signedIn else { toast("Sign in to start."); signIn(); return }
        var sid = current
        if sid == nil {
            guard let dir = draftProject else { toast("Open a folder first."); return }
            await loadModels()
            var body: [String: Any] = ["location": ["directory": dir], "agent": mode.agent, "permissions": mode.rules]
            if let m = model { body["model"] = ["id": m.id, "providerID": m.providerID] }
            do {
                guard let d = try await engine.data("/api/session", method: "POST", json: body) as? [String: Any], let row = Store.row(d) else { return }
                if !sessions.contains(where: { $0.id == row.id }) { sessions.insert(row, at: 0) }
                messages[row.id] = []
                loaded.insert(row.id)
                current = row.id; draftProject = nil
                sid = row.id
            } catch { toast(error.localizedDescription); return }
        }
        guard let id = sid else { return }
        busy.insert(id)
        do { try await engine.call("/api/session/\(id)/prompt", method: "POST", json: ["text": text]) }
        catch { busy.remove(id); toast(error.localizedDescription) }
    }

    func stop() {
        guard let id = current else { return }
        Task { _ = try? await engine.call("/api/session/\(id)/interrupt", method: "POST") }
    }

    func reply(_ ask: PermissionAsk, _ decision: String) {
        asks.removeAll { $0.id == ask.id }
        Task { _ = try? await engine.call("/api/session/\(ask.sessionID)/permission/\(ask.id)/reply", method: "POST", json: ["decision": decision]) }
    }

    func choose(_ m: ModelChoice) {
        model = m
        UserDefaults.standard.set(m.key, forKey: "model")
        if let id = current { Task { _ = try? await engine.call("/api/session/\(id)/model", method: "POST", json: ["model": ["id": m.id, "providerID": m.providerID]]) } }
    }

    private func applyMode() async {
        guard let id = current else { return }
        _ = try? await engine.call("/api/session/\(id)", method: "PATCH", json: ["permissions": mode.rules])
        _ = try? await engine.call("/api/session/\(id)/agent", method: "POST", json: ["agent": mode.agent])
    }

    // MARK: the lamport account

    nonisolated static let provider = "lamport"
    nonisolated static let localProviders: Set<String> = ["ollama", "lmstudio", "llama.cpp", "llamacpp"]

    /// lamport models the plan doesn't include, from the list lamport.si last sent, so the picker can say they exist
    private func lockedLamport(besides open: [ModelChoice]) -> [ModelChoice] {
        guard signedIn, let d = UserDefaults.standard.data(forKey: "lamportModels"),
              let list = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        return list.compactMap { m in
            guard (m["available"] as? Bool) == false, let id = m["id"] as? String, !open.contains(where: { $0.id == id }) else { return nil }
            return ModelChoice(id: id, providerID: Store.provider, name: m["name"] as? String ?? id, locked: true)
        }
    }

    /// device login: lamport.si hands out a code, the member approves it in the browser, the app collects its own token
    func signIn() {
        guard !signingIn else { return }
        signingIn = true; authError = nil
        Task {
            defer { signingIn = false }
            do {
                let start = try await API.call("/api/device/start", method: "POST", json: [:])
                guard let code = start["code"] as? String else { throw API.HTTPError(status: 0, message: "lamport.si did not hand out a code.") }
                var comps = URLComponents(url: API.siteURL("/device"), resolvingAgainstBaseURL: false)!
                comps.queryItems = [URLQueryItem(name: "code", value: code)]
                NSWorkspace.shared.open(comps.url!)
                for _ in 0..<300 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    guard signingIn else { return }
                    let r = try await API.call("/api/device/\(code)")
                    guard let t = r["token"] as? String else { continue }
                    Keychain.set(t, for: API.tokenKey)
                    who = (r["who"] as? String)?.nilIfEmpty
                    UserDefaults.standard.set(who, forKey: API.whoKey)
                    signedIn = true
                    // a fresh sign-in starts on lamport's default model; a pick made after this sticks again
                    UserDefaults.standard.removeObject(forKey: "model")
                    await connectLamport()
                    await loadModels()
                    toast("Signed in\(who.map { " as \($0)" } ?? "")")
                    NSApp.activate(ignoringOtherApps: true)
                    return
                }
                authError = "The sign-in took too long. Try again."
            } catch { authError = error.localizedDescription }
        }
    }
    func cancelSignIn() { signingIn = false }

    func signOut(local: Bool = false) {
        if !local, API.token != nil { let r = API.request("/api/device/signout", method: "POST", json: [:]); Task { _ = try? await URLSession.shared.data(for: r) } }
        Keychain.delete(API.tokenKey)
        UserDefaults.standard.removeObject(forKey: API.whoKey)
        signedIn = false; who = nil; usage = nil
        if model?.isLamport == true { UserDefaults.standard.removeObject(forKey: "model") }
        Task { await connectLamport(); await loadModels() }
    }

    /// the engine reaches models through lamport.si: an openai-compatible provider at API.proxyURL whose key is the
    /// member's own app token. provider keys stay on the server; signed out, the provider and its key are taken away
    func connectLamport() async {
        guard engine.state == .ready else { return }
        guard let token = API.token else { await configureLamport(models: nil); await setLamportKey(nil); await settle(false); return }
        var list: [[String: Any]]
        do {
            list = try await API.call("/api/v1/models")["data"] as? [[String: Any]] ?? []
            if let d = try? JSONSerialization.data(withJSONObject: list) { UserDefaults.standard.set(d, forKey: "lamportModels") }
        } catch let e as API.HTTPError where e.status == 401 {
            signOut(local: true); authError = "Your sign-in has expired. Sign in again."; return
        } catch {
            // offline: keep the provider with the models we last saw, the engine will say so if a call fails
            Log.write("lamport models: \(error.localizedDescription)")
            list = (UserDefaults.standard.data(forKey: "lamportModels").flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
        }
        await setLamportKey(token)
        await configureLamport(models: list)
        await refreshUsage()
        await settle(!list.isEmpty)
    }

    /// the engine picks up its config file on its own; wait until lamport's models come or go before the picker reads them
    private func settle(_ on: Bool) async {
        for _ in 0..<20 {
            let have = (try? await engine.data("/api/model") as? [[String: Any]])?.contains { $0["providerID"] as? String == Store.provider } ?? false
            if have == on { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    /// the provider block in the engine's own global config, merged into whatever else is there
    private func configureLamport(models list: [[String: Any]]?) async {
        guard let dirs = try? await engine.call("/api/config") as? [[String: Any]],
              let dir = dirs.first(where: { $0["type"] as? String == "directory" })?["path"] as? String else { Log.write("lamport: no engine config folder"); return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        let file = folder.appendingPathComponent(folder.lastPathComponent + ".json")
        var config = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var providers = config["providers"] as? [String: Any] ?? [:]
        let current = config["model"] as? String
        if let list, !list.isEmpty {
            var models: [String: Any] = [:]
            for m in list {
                guard let id = m["id"] as? String, (m["available"] as? Bool) != false else { continue }
                models[id] = ["name": m["name"] as? String ?? id, "capabilities": ["tools": true, "temperature": true], "limit": ["context": m["context_length"] as? Int ?? 128_000, "output": m["max_output"] as? Int ?? 32_000]]
            }
            providers[Store.provider] = ["name": "Lamport", "package": "@lamport/ai/providers/openai-compatible", "settings": ["baseURL": API.proxyURL.absoluteString], "models": models]
            let first = list.first { ($0["available"] as? Bool) != false }?["id"] as? String
            if let first, current == nil || current!.hasPrefix(Store.provider + "/") && models[String(current!.dropFirst(Store.provider.count + 1))] == nil { config["model"] = "\(Store.provider)/\(first)" }
        } else {
            providers[Store.provider] = nil
            if current?.hasPrefix(Store.provider + "/") == true { config["model"] = nil }
        }
        config["providers"] = providers.isEmpty ? nil : providers
        guard let out = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) else { return }
        if (try? Data(contentsOf: file)) == out { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do { try out.write(to: file, options: .atomic); Log.write("lamport provider \(list?.isEmpty == false ? "on" : "off")") } catch { Log.write("lamport config: \(error.localizedDescription)") }
    }

    /// the token as the provider's key in the engine's credential store; nil takes it out
    private func setLamportKey(_ token: String?) async {
        let all = (try? await engine.data("/api/credential") as? [[String: Any]]) ?? []
        let ours = all.filter { $0["integrationID"] as? String == Store.provider }
        if let token, ours.count == 1, ours[0]["active"] as? Bool == true, (ours[0]["value"] as? [String: Any])?["key"] as? String == token { return }
        for c in ours { if let id = c["id"] as? String { _ = try? await engine.call("/api/credential/\(id)", method: "DELETE") } }
        guard let token else { return }
        do { try await engine.call("/api/credential", method: "POST", json: ["integrationID": Store.provider, "label": "Lamport", "value": ["type": "key", "key": token]]) }
        catch { Log.write("lamport key: \(error.localizedDescription)") }
    }

    nonisolated static func tokens(_ n: Int) -> String { n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)k" : "\(n)" }

    func refreshUsage() async {
        guard API.token != nil, let u = try? await API.call("/api/v1/usage") else { return }
        let turns = u["turns"] as? [String: Any], tokens = u["tokens"] as? [String: Any]
        usage = Usage(pro: u["pro"] as? Bool ?? false, turns: turns?["used"] as? Int ?? 0, turnLimit: turns?["limit"] as? Int ?? 0, tokens: tokens?["used"] as? Int ?? 0, tokenLimit: tokens?["limit"] as? Int ?? 0)
    }

    // MARK: the side panel

    func refreshSide() async {
        guard let dir = directory else { diffs = []; branch = nil; return }
        let vcs = try? await engine.data("/api/vcs", query: [("location[directory]", dir)]) as? [String: Any]
        branch = vcs?["branch"] as? String
        do {
            let list = try await engine.data("/api/vcs/diff", query: [("location[directory]", dir), ("mode", "working")]) as? [[String: Any]] ?? []
            diffs = list.map { FileDiff(file: $0["file"] as? String ?? "", patch: $0["patch"] as? String ?? "", additions: $0["additions"] as? Int ?? 0, deletions: $0["deletions"] as? Int ?? 0, status: $0["status"] as? String ?? "modified") }
            diffNote = nil
        } catch {
            diffs = []
            diffNote = "Not a git repository. Changes show up here once the folder is under git."
        }
    }
    var diffTotals: (add: Int, del: Int) { diffs.reduce((0, 0)) { ($0.0 + $1.additions, $0.1 + $1.deletions) } }

    func toast(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if toast == s { toast = nil } }
    }

    // MARK: the event stream

    private func listen() async {
        while engine.state == .ready {
            do {
                for try await e in engine.events() { handle(e) }
            } catch { Log.write("events dropped: \(error.localizedDescription)") }
            try? await Task.sleep(nanoseconds: 800_000_000)
            for id in busy { await loadMessages(id) }
        }
    }

    private func handle(_ e: [String: Any]) {
        guard let type = e["type"] as? String, let d = e["data"] as? [String: Any] else { return }
        let sid = d["sessionID"] as? String
        switch type {
        case "session.created":
            if var row = Store.row(d), !sessions.contains(where: { $0.id == row.id }) {
                if row.directory.isEmpty, let dir = (e["location"] as? [String: Any])?["directory"] as? String { row.directory = dir }
                sessions.insert(row, at: 0)
            }
        case "session.updated", "session.title.updated", "session.renamed":
            if let sid, let i = sessions.firstIndex(where: { $0.id == sid }), let t = (d["title"] ?? (d["info"] as? [String: Any])?["title"]) as? String, !t.isEmpty { sessions[i].title = t }
        case "session.deleted":
            if let sid { sessions.removeAll { $0.id == sid } }
        case "session.inbox.enqueued":
            guard let sid, let item = d["item"] as? [String: Any], item["type"] as? String == "user", let mid = d["inboxID"] as? String else { break }
            let text = (item["payload"] as? [String: Any])?["text"] as? String ?? ""
            edit(sid) { list in if !list.contains(where: { $0.id == mid }) { list.append(Message(id: mid, role: .user, text: text)) } }
            touch(sid)
        case "session.execution.started":
            if let sid { busy.insert(sid); touch(sid) }
        case "session.execution.succeeded":
            if let sid { finished(sid) }
        case "session.execution.failed", "session.execution.interrupted":
            guard let sid else { break }
            let note = type.hasSuffix("interrupted") ? "Stopped." : (Store.errorText(d["error"]).nilIfEmpty ?? "The run failed.")
            edit(sid) { $0.append(Message(id: e["id"] as? String ?? UUID().uuidString, role: .notice, text: note)) }
            finished(sid)
        case "session.step.started":
            guard let sid, let mid = d["assistantMessageID"] as? String else { break }
            edit(sid) { list in if !list.contains(where: { $0.id == mid }) { list.append(Message(id: mid, role: .assistant)) } }
        case "session.reasoning.started", "session.reasoning.delta", "session.reasoning.ended":
            guard let sid, let mid = d["assistantMessageID"] as? String else { break }
            let bid = "\(mid)-r\(d["ordinal"] as? Int ?? 0)"
            block(sid, mid, bid, make: .thinking(id: bid, text: "", done: false)) { b in
                guard case .thinking(_, let text, _) = b else { return b }
                if type.hasSuffix("delta") { return .thinking(id: bid, text: text + (d["delta"] as? String ?? ""), done: false) }
                if type.hasSuffix("ended") { return .thinking(id: bid, text: d["text"] as? String ?? text, done: true) }
                return b
            }
        case "session.text.started", "session.text.delta", "session.text.ended":
            guard let sid, let mid = d["assistantMessageID"] as? String else { break }
            let bid = "\(mid)-t\(d["ordinal"] as? Int ?? 0)"
            block(sid, mid, bid, make: .text(id: bid, text: "")) { b in
                guard case .text(_, let text) = b else { return b }
                if type.hasSuffix("delta") { return .text(id: bid, text: text + (d["delta"] as? String ?? "")) }
                if type.hasSuffix("ended") { return .text(id: bid, text: d["text"] as? String ?? text) }
                return b
            }
        case _ where type.hasPrefix("session.tool."):
            guard let sid, let mid = d["assistantMessageID"] as? String, let tid = d["id"] as? String else { break }
            block(sid, mid, tid, make: .tool(ToolCall(id: tid, name: d["name"] as? String ?? "tool"))) { b in
                guard case .tool(var t) = b else { return b }
                if let n = d["name"] as? String { t.name = n }
                if let i = d["input"] as? [String: Any] { t.input = i }
                switch type {
                case "session.tool.input.ended":
                    if t.input.isEmpty, let s = d["text"] as? String, let j = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] { t.input = j }
                case "session.tool.called", "session.tool.progress": t.status = .running
                case "session.tool.success": t.status = .done; t.output = Store.text(d["content"])
                case _ where type.hasSuffix("error") || type.hasSuffix("failed"):
                    t.status = .failed; t.output = Store.text(d["content"]) + Store.errorText(d["error"])
                default: break
                }
                return .tool(t)
            }
        case "session.step.ended":
            if let sid, let c = d["cost"] as? Double { cost[sid, default: 0] += c }
            if let files = d["files"] as? [String], !files.isEmpty { Task { await refreshSide() } }
        case "permission.asked":
            addAsk(d)
            if !NSApp.isActive { NSApp.dockTile.badgeLabel = "!"; NSApp.requestUserAttention(.informationalRequest) }
        case "permission.replied":
            if let rid = d["requestID"] as? String { asks.removeAll { $0.id == rid } }
        default: break
        }
    }

    private func finished(_ sid: String) {
        busy.remove(sid)
        if signedIn { Task { await refreshUsage() } }
        asks.removeAll { $0.sessionID == sid }
        touch(sid)
        Task { await refreshSide() }
        if !NSApp.isActive { NSApp.dockTile.badgeLabel = "●" }
    }

    private func addAsk(_ d: [String: Any]) {
        guard let id = d["id"] as? String, let sid = d["sessionID"] as? String, !asks.contains(where: { $0.id == id }) else { return }
        asks.append(PermissionAsk(id: id, sessionID: sid, action: d["action"] as? String ?? "", resources: d["resources"] as? [String] ?? [], save: d["save"] as? [String] ?? []))
    }

    private func touch(_ sid: String) {
        if let i = sessions.firstIndex(where: { $0.id == sid }) { sessions[i].updated = Date() }
    }

    private func edit(_ sid: String, _ f: (inout [Message]) -> Void) {
        var list = messages[sid] ?? []
        f(&list)
        messages[sid] = list
    }

    /// find or make the block `bid` inside assistant message `mid`, then update it in place
    private func block(_ sid: String, _ mid: String, _ bid: String, make: Block, _ f: (Block) -> Block) {
        edit(sid) { list in
            var mi = list.firstIndex { $0.id == mid }
            if mi == nil { list.append(Message(id: mid, role: .assistant)); mi = list.count - 1 }
            guard let m = mi else { return }
            if let bi = list[m].blocks.firstIndex(where: { $0.id == bid }) { list[m].blocks[bi] = f(list[m].blocks[bi]) }
            else { list[m].blocks.append(f(make)) }
        }
    }

    nonisolated static func text(_ content: Any?) -> String {
        ((content as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
    nonisolated static func errorText(_ e: Any?) -> String {
        guard let e = e as? [String: Any] else { return (e as? String) ?? "" }
        return (e["message"] as? String) ?? ((e["data"] as? [String: Any])?["message"] as? String) ?? ""
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
