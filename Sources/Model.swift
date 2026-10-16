import SwiftUI
import AppKit

enum ToolStatus { case running, ok, fail }
struct ToolRow: Identifiable {
    let id: String
    var name: String
    var detail: String
    var status: ToolStatus = .running
    var note: String? = nil
    var diff: (old: [String], new: [String])? = nil
    var out: [String] = []
    var approval = false          // the member confirms before it runs
    var decision: Bool? = nil     // nil while waiting
    var label: String {
        switch name { case "run_command": "Run"; case "write_file": "Write"; case "edit_file": "Edit"; case "read_file": "Read"; case "search": "Search"; case "delete_file": "Delete"; default: "List" }
    }
    static func detail(_ name: String, _ a: [String: Any]) -> String {
        switch name {
        case "run_command": return a["command"] as? String ?? ""
        case "search": return "/\(a["pattern"] as? String ?? "")/" + ((a["glob"] as? String).map { " in \($0)" } ?? "")
        case "list_files": return a["pattern"] as? String ?? "."
        default: return (a["path"] as? String ?? "") + (name == "read_file" ? ((a["offset"] as? Int).map { ":\($0)" } ?? "") : "")
        }
    }
}
struct TodoItem: Identifiable { var id: String { text }; var text: String; var status: String }
struct AgentGroup: Identifiable { let id: String; var brief: String; var mode: String; var status: String; var parts: [Part] = []; var open = true }
indirect enum Part: Identifiable {
    case text(id: String, String), tool(ToolRow), agent(AgentGroup), todo(id: String, [TodoItem])
    var id: String { switch self { case .text(let id, _): id; case .tool(let r): r.id; case .agent(let g): "agent-\(g.id)"; case .todo(let id, _): id } }
}
/// a background job: a dev server, a watcher, a long test run; kept across turns, reported to the agent on the next one
@MainActor final class Job: ObservableObject, Identifiable {
    let id: String; let command: String; let started = Date()
    @Published var status = "running"; @Published var exit: Int32? = nil; @Published var tail: [String] = []
    var reported = false; var run: ShellRun? = nil
    init(id: String, command: String) { self.id = id; self.command = command }
    func line(_ l: String) { tail.append(l); if tail.count > 400 { tail.removeFirst(tail.count - 400) } }
    var summary: String { "\(status)\(exit.map { " exit \($0)" } ?? "")\n" + tail.suffix(60).joined(separator: "\n") }
}
struct Turn: Identifiable {
    let id = UUID()
    enum Role { case user, assistant }
    var role: Role
    var text = ""
    var parts: [Part] = []
    var pending = false
    var at = Date()
}
struct FileNode: Identifiable { var id: String { path }; var path: String; var depth: Int; var isLast: Bool }
struct ModelChoice: Identifiable, Hashable { let id: String; let label: String; let note: String; let pro: Bool; let available: Bool }
struct Session: Identifiable { let id: String; let name: String; let kind: String; let root: String?; let updated: Date }
struct Slash { let cmd: String; let hint: String; let prompt: String? }
let SLASH: [Slash] = [
    Slash(cmd: "/init", hint: "explore the project and write LAMPORT.md, the notes every turn starts from", prompt: "Explore this project (list the files, read the key ones) and write LAMPORT.md at the root: what it is, how to run, build and test it, the structure, the conventions to keep. Under 60 lines, plain and specific. Then call done."),
    Slash(cmd: "/test", hint: "run the tests (or type check and build) and fix what fails", prompt: "Run the project's tests; if there are none, run the type check and the build. Fix what fails, re-run until green, then summarise."),
    Slash(cmd: "/commit", hint: "stage your changes and commit with a terse message", prompt: "Run git status and git diff. Stage the files that belong to the current change and commit them with a terse lowercase message that says what changed. Do not push. If there is nothing to commit, say so."),
    Slash(cmd: "/clear", hint: "start a new session", prompt: nil),
]
let KIND_LABEL: [String: String] = ["dapp": "Full stack dapp", "program": "Solana program", "script": "Script"]

@MainActor
final class DeskModel: ObservableObject {
    // account
    @Published var signedIn = false
    @Published var who: String? = nil
    @Published var signingIn = false
    @Published var authError: String? = nil
    // project
    @Published var folder: URL? = nil
    @Published var projectId: String? = nil
    @Published var projectName: String? = nil
    @Published var kind = "dapp"
    @Published var model = "glm-5.3-flash"
    @Published var models: [ModelChoice] = []
    @Published var freeTurns = 20
    @Published var turnsLeft: Int? = nil
    @Published var served: String? = nil
    @Published var turns: [Turn] = []
    @Published var files: [String: String] = [:]
    @Published var selected: String? = nil
    @Published var busy = false
    @Published var prompt = ""
    @Published var sideTab = 0
    @Published var sessions: [Session] = []
    @Published var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentFolders") ?? []
    @Published var toast: String? = nil
    @Published var termOpen = false
    @Published var jobs: [Job] = []
    @Published var approvals: [String: (Bool) -> Void] = [:]
    var alwaysAllow: Set<String> = []
    let autoApprove = CommandLine.arguments.contains("--auto-approve")
    let runtime = LocalRuntime()
    private var streamTask: Task<Void, Never>? = nil
    private var autoFixes = 0
    private var runtimeWatch: Task<Void, Never>? = nil

    init() {
        signedIn = API.token != nil || API.isLocalDev
        who = UserDefaults.standard.string(forKey: "who")
        if API.isLocalDev && who == nil { who = "dev" }
        runtimeWatch = Task { [weak self] in
            for await _ in self!.runtime.$status.values { guard let self else { return }; if runtime.status == .failed && !busy && folder != nil && autoFixes < 2 && !runtime.log.isEmpty { try? await Task.sleep(for: .milliseconds(800)); if runtime.status == .failed && !busy { fixIt() } } }
        }
        // launch arguments, for scripts and tests: --folder <path> opens it, --prompt <text> sends a first request
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--folder"), i + 1 < args.count {
            Task { await loadMeta(); await openFolder(URL(fileURLWithPath: args[i + 1])); if let j = args.firstIndex(of: "--prompt"), j + 1 < args.count { send(args[j + 1]) } }
        }
    }

    var paths: [String] { files.keys.sorted { a, b in let da = a.split(separator: "/").count, db = b.split(separator: "/").count; return da != db ? da > db : a < b } }
    var tree: [FileNode] { let ps = paths; return ps.enumerated().map { i, p in let depth = p.split(separator: "/").count - 1; return FileNode(path: p, depth: depth, isLast: i == ps.count - 1 || (ps[i + 1].split(separator: "/").count - 1) < depth) } }
    var currentModel: ModelChoice? { models.first { $0.id == model } }
    var folderName: String? { folder?.lastPathComponent }
    var isStatic: Bool { files["index.html"] != nil && files["package.json"] == nil }
    var canPreview: Bool { kind != "program" && (isStatic || files["package.json"] != nil) }
    var staticDoc: String? {
        guard isStatic, var html = files["index.html"] else { return nil }
        for (p, c) in files where p.hasSuffix(".css") { html = html.replacingOccurrences(of: "<link rel=\"stylesheet\" href=\"\(p)\">", with: "<style>\(c)</style>").replacingOccurrences(of: "<link rel=\"stylesheet\" href=\"./\(p)\">", with: "<style>\(c)</style>") }
        for (p, c) in files where p.hasSuffix(".js") { for src in [p, "./\(p)"] { html = html.replacingOccurrences(of: "src=\"\(src)\"></script>", with: ">\(c)</script>") } }
        return html
    }

    func say(_ s: String) { toast = s; Task { try? await Task.sleep(for: .seconds(4)); if toast == s { toast = nil } } }

    // ---- account
    func loadMeta() async {
        if let r = try? await API.call("/api/build/models") {
            models = (r["models"] as? [[String: Any]] ?? []).map { ModelChoice(id: $0["id"] as? String ?? "", label: $0["label"] as? String ?? "", note: $0["note"] as? String ?? "", pro: $0["pro"] as? Bool ?? false, available: $0["available"] as? Bool ?? true) }
            freeTurns = r["freeTurns"] as? Int ?? 20
        }
        if signedIn, let me = try? await API.call("/api/me") { if let e = me["email"] as? String { who = e; UserDefaults.standard.set(e, forKey: "who") } else if me["id"] == nil || me["id"] is NSNull { if !API.isLocalDev { signOut(local: true) } } }
        await loadSessions()
    }
    func loadSessions() async {
        guard signedIn, let r = try? await API.call("/api/projects") else { return }
        sessions = (r["projects"] as? [[String: Any]] ?? []).map { Session(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "Untitled", kind: $0["kind"] as? String ?? "dapp", root: $0["root"] as? String, updated: Date(timeIntervalSince1970: (($0["updated"] as? Double) ?? 0) / 1000)) }
    }
    func signIn() {
        guard !signingIn else { return }
        signingIn = true; authError = nil
        Task {
            defer { signingIn = false }
            do {
                let start = try await API.call("/api/device/start", method: "POST", json: [:])
                guard let code = start["code"] as? String else { throw API.HTTPError(status: 0, message: "no code") }
                var comps = URLComponents(url: API.siteURL("/device"), resolvingAgainstBaseURL: false)!; comps.queryItems = [URLQueryItem(name: "code", value: code)]
                NSWorkspace.shared.open(comps.url!)
                for _ in 0..<300 {
                    try await Task.sleep(for: .seconds(2))
                    guard signingIn else { return }
                    let r = try await API.call("/api/device/\(code)")
                    if let t = r["token"] as? String { Keychain.set(t, for: "appToken"); who = r["who"] as? String; UserDefaults.standard.set(who, forKey: "who"); signedIn = true; await loadMeta(); say("Signed in"); return }
                }
                authError = "The sign-in took too long. Try again."
            } catch { authError = error.localizedDescription }
        }
    }
    func cancelSignIn() { signingIn = false }
    func signOut(local: Bool = false) {
        if !local, API.token != nil { Task { _ = try? await API.call("/api/device/signout", method: "POST", json: [:]) } }
        Keychain.delete("appToken"); UserDefaults.standard.removeObject(forKey: "who")
        signedIn = API.isLocalDev; who = API.isLocalDev ? "dev" : nil; sessions = []; turns = []; projectId = nil; projectName = nil
    }

    // ---- folders and sessions
    func pickFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false; p.canCreateDirectories = true; p.prompt = "Open"; p.message = "Choose the project folder the agent will work in"
        if p.runModal() == .OK, let u = p.url { Task { await openFolder(u) } }
    }
    func openFolder(_ u: URL, session: Session? = nil) async {
        await runtime.stop(); streamTask?.cancel()
        folder = u; files = [:]; selected = nil; turns = []; projectId = nil; projectName = nil; autoFixes = 0; sideTab = 0
        var rec = [u.path] + recent.filter { $0 != u.path }; if rec.count > 8 { rec = Array(rec.prefix(8)) }
        recent = rec; UserDefaults.standard.set(rec, forKey: "recentFolders")
        let tools = LocalTools(root: u)
        let tree = await Task.detached { tools.readTree() }.value
        files = tree
        let ps = paths
        selected = ps.first { $0.range(of: #"README\.md$|App\.tsx$|index\.ts$|lib\.rs$|package\.json$"#, options: .regularExpression) != nil } ?? ps.first
        if tree["Anchor.toml"] != nil || tree.keys.contains(where: { $0.range(of: #"programs/.*/lib\.rs$"#, options: .regularExpression) != nil }) { kind = "program" }
        else if tree["index.html"] != nil || (tree["package.json"]?.range(of: #""(react|vite|next|svelte|vue|@solana/wallet-adapter-react)""#, options: .regularExpression) != nil) { kind = "dapp" }
        else if tree["package.json"] != nil { kind = "script" }
        if signedIn && sessions.isEmpty { await loadSessions() }
        let known = session ?? sessions.first { $0.root == u.path }
        if let known, let p = try? await API.call("/api/projects/\(known.id)") {
            projectId = known.id; projectName = p["name"] as? String; kind = p["kind"] as? String ?? kind; model = p["model"] as? String ?? model
            turns = (p["chat"] as? [[String: Any]] ?? []).map { c in Turn(role: (c["role"] as? String) == "user" ? .user : .assistant, text: c["text"] as? String ?? "", at: Date(timeIntervalSince1970: ((c["at"] as? Double) ?? 0) / 1000)) }
        }
        say("Opened \(u.lastPathComponent)")
    }
    /// a session from the web desk has no folder yet: pick one and write the project's files into it
    func checkOut(_ s: Session) {
        if let r = s.root, FileManager.default.fileExists(atPath: r) { Task { await openFolder(URL(fileURLWithPath: r), session: s) }; return }
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = "Use this folder"; p.message = "“\(s.name)” lives on lamport.si. Pick a folder on your Mac; its files are written there and the session continues locally."
        guard p.runModal() == .OK, let u = p.url else { return }
        Task {
            if let proj = try? await API.call("/api/projects/\(s.id)"), let fs = proj["files"] as? [String: String] {
                let tools = LocalTools(root: u); for (path, c) in fs { _ = try? tools.write(path, c) }
            }
            await openFolder(u, session: s)
        }
    }
    func newSession() { streamTask?.cancel(); Task { await runtime.stop() }; turns = []; projectId = nil; projectName = nil; autoFixes = 0; say("New session in \(folderName ?? "no folder")") }
    func deleteSession(_ s: Session) { Task { _ = try? await API.call("/api/projects/\(s.id)", method: "DELETE"); if projectId == s.id { newSession() }; await loadSessions() } }
    func saveFile(_ path: String, _ content: String) {
        files[path] = content
        guard let folder else { return }
        let tools = LocalTools(root: folder); Task.detached { _ = try? tools.write(path, content) }
    }

    // ---- the agent
    private func withLast(_ f: (inout Turn) -> Void) { guard !turns.isEmpty else { return }; f(&turns[turns.count - 1]) }
    /// the parts list an event belongs to: the turn's own, or a sub-agent's group inside it
    private func withParts(_ agent: String?, _ f: (inout [Part]) -> Void) {
        withLast { t in
            guard let agent else { f(&t.parts); return }
            for i in t.parts.indices { if case .agent(var g) = t.parts[i], g.id == agent { f(&g.parts); t.parts[i] = .agent(g); return } }
            f(&t.parts)
        }
    }
    private func appendText(_ s: String, agent: String? = nil) { withParts(agent) { parts in if case .text(let id, let old)? = parts.last { parts[parts.count - 1] = .text(id: id, old + s) } else { parts.append(.text(id: UUID().uuidString, s)) } } }
    private func addTool(_ r: ToolRow, agent: String? = nil) { withParts(agent) { $0.append(.tool(r)) } }
    private func patchTool(_ id: String, agent: String? = nil, _ f: (inout ToolRow) -> Void) { withParts(agent) { parts in for i in parts.indices { if case .tool(var r) = parts[i], r.id == id { f(&r); parts[i] = .tool(r) } } } }
    private func allTools(_ parts: [Part]) -> [ToolRow] { parts.flatMap { p -> [ToolRow] in switch p { case .tool(let r): return [r]; case .agent(let g): return allTools(g.parts); default: return [] } } }
    private var lastRunning: ToolRow? { allTools(turns.last?.parts ?? []).reversed().first { $0.status == .running } }
    var waitingApproval: ToolRow? { allTools(turns.last?.parts ?? []).first { $0.approval && $0.decision == nil && $0.status == .running } }

    func send(_ raw: String, auto: Bool = false) {
        let q0 = raw.trimmingCharacters(in: .whitespacesAndNewlines); guard !q0.isEmpty, !busy else { return }
        guard signedIn else { signIn(); return }
        guard let folder else { pickFolder(); return }
        let word = q0.split(separator: " ").first.map(String.init) ?? q0
        let slash = q0.hasPrefix("/") ? SLASH.first { $0.cmd == word } : nil
        if let slash, slash.cmd == "/clear" { prompt = ""; newSession(); return }
        let rest = q0.dropFirst(slash?.cmd.count ?? 0).trimmingCharacters(in: .whitespaces)
        let q = slash?.prompt.map { rest.isEmpty ? $0 : "\($0)\n\n\(rest)" } ?? q0
        if !auto { autoFixes = 0 }
        prompt = ""; busy = true
        turns.append(Turn(role: .user, text: slash != nil ? q0 : q)); turns.append(Turn(role: .assistant, pending: true))
        let notes = ["LAMPORT.md", "CLAUDE.md", "AGENTS.md"].compactMap { files[$0] }.first
        var body: [String: Any] = ["kind": kind, "model": model, "prompt": q, "root": folder.path, "name": folder.lastPathComponent]
        if let projectId { body["projectId"] = projectId }
        if let notes { body["notes"] = notes }
        let finished = jobs.filter { !$0.reported && $0.status != "running" }
        if !finished.isEmpty { body["jobs"] = finished.map { ["id": $0.id, "command": $0.command, "status": $0.status, "exit": $0.exit as Any, "tail": $0.tail.suffix(30).joined(separator: "\n")] }; finished.forEach { $0.reported = true } }
        streamTask = Task { [weak self] in
            guard let self else { return }
            var sid: String? = nil; var pending: [Task<Void, Never>] = []; var wrote: [String] = []; var wrotePkg = false
            do {
                for try await ev in API.events("/api/build/local", json: body) {
                    guard let type = ev["type"] as? String else { continue }
                    switch type {
                    case "project":
                        projectId = ev["id"] as? String; projectName = ev["name"] as? String; sid = ev["session"] as? String
                        if let n = ev["turnsLeft"] as? Int { turnsLeft = n }
                    case "served": served = (ev["model"] as? String ?? "") + ((ev["provider"] as? String).map { " · \($0.lowercased())" } ?? "")
                    case "text": appendText(ev["delta"] as? String ?? "", agent: ev["agent"] as? String)
                    case "agent":
                        guard let id = ev["id"] as? String else { continue }
                        let status = ev["status"] as? String ?? "running"
                        if status == "running" { withParts(ev["agent"] as? String) { $0.append(.agent(AgentGroup(id: id, brief: ev["brief"] as? String ?? "", mode: ev["mode"] as? String ?? "explore", status: "running"))) } }
                        else { withLast { t in for i in t.parts.indices { if case .agent(var g) = t.parts[i], g.id == id { g.status = status; g.open = false; t.parts[i] = .agent(g) } } } }
                    case "todo":
                        let items = (ev["items"] as? [[String: Any]] ?? []).map { TodoItem(text: $0["text"] as? String ?? "", status: $0["status"] as? String ?? "pending") }
                        withLast { t in if let i = t.parts.firstIndex(where: { if case .todo = $0 { return true }; return false }) { t.parts[i] = .todo(id: "todo", items) } else { t.parts.append(.todo(id: "todo", items)) } }
                    case "tool":
                        guard let sid, let id = ev["id"] as? String, let name = ev["name"] as? String else { continue }
                        let args = ev["args"] as? [String: Any] ?? [:]
                        let tag = ev["agent"] as? String
                        if name == "web_fetch" || name == "spawn_agent" { addTool(ToolRow(id: id, name: name, detail: name == "web_fetch" ? (args["url"] as? String ?? "") : (args["brief"] as? String ?? "").prefix(80) + "…"), agent: tag); continue }
                        pending.append(Task { await self.runTool(sid: sid, id: id, name: name, args: args, approval: ev["approval"] as? Bool ?? false, agent: tag) })
                    case "tool_result":
                        if let id = ev["id"] as? String, let name = ev["name"] as? String, name == "web_fetch" || name == "spawn_agent" { patchTool(id, agent: ev["agent"] as? String) { $0.status = (ev["ok"] as? Bool ?? true) ? .ok : .fail; if name == "web_fetch" { $0.note = String((ev["preview"] as? String ?? "").split(separator: "\n").first ?? "") } } }
                    case "file":
                        if let p = ev["path"] as? String { wrote.append(p); if p == "package.json" { wrotePkg = true } }
                    case "done":
                        let fin = (ev["final"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !fin.isEmpty { appendText("\n\n" + fin) }
                        withLast { $0.pending = false; $0.text = ev["summary"] as? String ?? "" }
                        let writes = ev["writes"] as? Int ?? 0
                        if writes > 0, kind != "program" {
                            let fl = ev["files"] as? [String] ?? []
                            if fl.contains("package.json"), wrotePkg || [.idle, .failed, .exited].contains(runtime.status) { Task { try? await Task.sleep(for: .milliseconds(50)); await self.startRun(wrotePkg && self.runtime.status != .idle ? "package.json changed, installing again" : "installing and starting the project") } }
                            else if fl.contains("index.html") || runtime.status == .running { sideTab = 1 }
                        }
                    case "error": appendText("\n\n" + (ev["message"] as? String ?? "The build stopped on an error.")); withLast { $0.pending = false }
                    default: break
                    }
                }
            } catch { if !(error is CancellationError) { appendText("\n\nCould not reach the build desk: \(error.localizedDescription)") } }
            for t in pending { await t.value }
            withLast { $0.pending = false }
            busy = false
            if !wrote.isEmpty, let folder = self.folder { let tools = LocalTools(root: folder); let fresh = await Task.detached { tools.readTree() }.value; files = fresh; if selected == nil || files[selected!] == nil { selected = wrote.last } }
            await loadSessions()
        }
    }
    func stop() { streamTask?.cancel(); busy = false; withLast { $0.pending = false }; for (_, f) in approvals { f(false) }; approvals = [:] }
    func decide(_ id: String, _ allow: Bool, always: Bool = false) {
        if always, let r = allTools(turns.last?.parts ?? []).first(where: { $0.id == id }) { alwaysAllow.insert(r.detail.split(separator: " ").prefix(2).joined(separator: " ")) }
        approvals[id]?(allow)
    }
    func stopJob(_ j: Job) { j.run?.stop(); j.status = "stopped" }
    func clearJobs() { jobs.removeAll { $0.status != "running" } }
    private func runTool(sid: String, id: String, name: String, args: [String: Any], approval: Bool = false, agent: String? = nil) async {
        var row = ToolRow(id: id, name: name, detail: ToolRow.detail(name, args))
        if name == "edit_file" { row.diff = ((args["old_string"] as? String ?? "").components(separatedBy: "\n"), (args["new_string"] as? String ?? "").components(separatedBy: "\n")) }
        if name == "job_status" || name == "job_stop" { row.detail = jobs.first { $0.id == (args["id"] as? String ?? "") }?.command ?? (args["id"] as? String ?? "") }
        if (args["background"] as? Bool) == true { row.note = "background" }
        let cmd0 = args["command"] as? String ?? ""
        let key = cmd0.split(separator: " ").prefix(2).joined(separator: " ")
        row.approval = approval && !autoApprove && !alwaysAllow.contains(key)
        addTool(row, agent: agent)
        if row.approval {
            let allowed = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in approvals[id] = { c.resume(returning: $0) } }
            approvals[id] = nil
            patchTool(id, agent: agent) { $0.decision = allowed; if !allowed { $0.status = .fail; $0.note = "declined" } }
            if !allowed { await post(sid, id, "tool failed: the member declined this command; do not retry it another way"); return }
        }
        guard let folder else { await post(sid, id, "tool failed: no folder is open"); patchTool(id, agent: agent) { $0.status = .fail }; return }
        let tools = LocalTools(root: folder)
        var result = ""; var ok = true; var newContent: String? = nil; var note: String? = nil
        if name == "job_status" || name == "job_stop" {
            if let j = jobs.first(where: { $0.id == (args["id"] as? String ?? "") }) { if name == "job_stop" { j.run?.stop(); j.status = "stopped"; result = "stopped \(j.command)" } else { result = j.summary; note = j.status } }
            else { ok = false; result = "tool failed: no such job" }
        } else if name == "run_command", (args["background"] as? Bool) == true {
            let jid = String(UUID().uuidString.prefix(8)); let job = Job(id: jid, command: cmd0)
            let run = ShellRun(root: folder, command: cmd0) { l in Task { @MainActor in job.line(l) } }
            run.process.terminationHandler = { p in Task { @MainActor in job.exit = p.terminationStatus; job.status = job.status == "stopped" ? "stopped" : (p.terminationStatus == 0 ? "exited" : "failed") } }
            job.run = run; jobs.append(job)
            do { try run.start(); try? await Task.sleep(for: .seconds(2)); result = "started background job \(jid): `\(cmd0)`\n\(job.summary)"; note = "job \(jid)" } catch { ok = false; result = "tool failed: \(error.localizedDescription)" }
        } else if name == "run_command" {
            let cmd = cmd0
            let timeout = min(900, Double(args["timeoutSec"] as? Int ?? 300))
            var lines: [String] = []; let lock = NSLock()
            let run = ShellRun(root: folder, command: cmd) { l in lock.lock(); lines.append(l); let snap = Array(lines.suffix(40)); let n = lines.count; lock.unlock(); if n % 5 == 1 { Task { @MainActor in self.patchTool(id, agent: agent) { $0.out = snap } } } }
            let r = await run.run(timeout: timeout)
            lock.lock(); let all = lines; lock.unlock()
            patchTool(id, agent: agent) { $0.out = Array(all.suffix(40)) }
            ok = r.code == 0
            result = "exit \(r.code.map(String.init) ?? "?")\(r.timedOut ? " (timed out)" : "")\n" + String(all.suffix(120).joined(separator: "\n").suffix(20_000))
        } else {
            let out: Result<String, Error> = await Task.detached {
                do {
                    switch name {
                    case "list_files": return .success(tools.list(args["pattern"] as? String))
                    case "read_file": return .success(try tools.read(args["path"] as? String ?? "", offset: args["offset"] as? Int, limit: args["limit"] as? Int))
                    case "write_file": return .success(try tools.write(args["path"] as? String ?? "", args["content"] as? String ?? ""))
                    case "edit_file": let (r, c) = try tools.edit(args["path"] as? String ?? "", old: args["old_string"] as? String ?? "", new: args["new_string"] as? String ?? "", all: args["replace_all"] as? Bool ?? false); return .success(r + "\u{0}" + c)
                    case "delete_file": return .success(try tools.delete(args["path"] as? String ?? ""))
                    case "search": return .success(tools.search(args["pattern"] as? String ?? "", glob: args["glob"] as? String))
                    default: return .failure(ToolError("unknown tool \(name)"))
                    }
                } catch { return .failure(error) }
            }.value
            switch out {
            case .success(let s):
                if name == "edit_file", let i = s.firstIndex(of: "\u{0}") { result = String(s[..<i]); newContent = String(s[s.index(after: i)...]) } else { result = s }
                if name == "search" { note = result == "no matches" ? "no matches" : "\(result.components(separatedBy: "\n").filter { $0.range(of: #"^[^:]+:\d+:"#, options: .regularExpression) != nil }.count) hits" }
                if name == "read_file" { note = "\(result.components(separatedBy: "\n").count) lines" }
                if name == "search", result.hasPrefix("bad regular") { ok = false }
            case .failure(let e): ok = false; result = "tool failed: \(e.localizedDescription)"
            }
        }
        if let p = args["path"] as? String {
            if name == "write_file", ok { files[p] = args["content"] as? String ?? ""; if selected == nil { selected = p } }
            if name == "edit_file", let c = newContent { files[p] = c }
            if name == "delete_file", ok { files[p] = nil; if selected == p { selected = nil } }
        }
        patchTool(id, agent: agent) { $0.status = ok ? .ok : .fail; if let note { $0.note = note }; if !ok, name != "run_command" { $0.note = String(result.prefix(90)) } }
        await post(sid, id, result)
    }
    private func post(_ sid: String, _ id: String, _ result: String) async { _ = try? await API.call("/api/build/local/\(sid)/tool/\(id)", method: "POST", json: ["result": String(result.prefix(120_000))]) }
    func fixIt() { guard !busy else { return }; autoFixes += 1; send("[local run] \(runtime.errorReport())\n\nFix the project so it installs and runs. Change only what the error needs.", auto: true) }

    // ---- running
    func startRun(_ why: String) async {
        guard let folder, files["package.json"] != nil else { return }
        sideTab = 1; say(why)
        await runtime.run(root: folder, files: files)
    }
    func doing() -> String {
        if let w = waitingApproval { return "waiting for your approval: \(w.detail.prefix(40))" }
        guard let r = lastRunning else { return turns.last?.parts.isEmpty == false ? "thinking" : "reading the brief" }
        switch r.name {
        case "run_command": return "running \(r.detail.prefix(40))"
        case "search": return "searching \(r.detail)"
        case "list_files": return "looking around"
        case "edit_file": return "editing \(r.detail)"
        case "write_file": return "writing \(r.detail)"
        case "read_file": return "reading \(r.detail)"
        case "web_fetch": return "fetching \(r.detail.prefix(50))"
        case "spawn_agent": return "a sub-agent is working"
        case "job_status": return "checking \(r.detail.prefix(40))"
        default: return "working"
        }
    }
}
