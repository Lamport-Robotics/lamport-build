import Foundation

/// the agent's tools over a folder on disk: the same semantics the server has for in-memory projects
struct LocalTools {
    let root: URL
    static let skip: Set<String> = ["node_modules", ".git", "dist", "build", "target", ".anchor", ".next", ".turbo", "coverage", ".DS_Store", "test-ledger", "DerivedData"]
    static let textExt: Set<String> = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "json", "md", "css", "scss", "html", "htm", "rs", "toml", "yml", "yaml", "txt", "env", "example", "sh", "svg", "lock", "gitignore", "npmrc", "nvmrc", "prettierrc", "eslintrc", "swift", "py", "go", "sql", "graphql", "xml", "plist"]

    func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }
    static func okPath(_ p: String) -> Bool { !p.isEmpty && !p.hasPrefix("/") && !p.contains("..") }

    /// every text file under the folder, dependency folders skipped
    func walk(maxFiles: Int = 2000) -> [String] {
        var out: [String] = []
        func rec(_ dir: URL, _ rel: String) {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for u in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if out.count >= maxFiles { return }
                let name = u.lastPathComponent
                if Self.skip.contains(name) { continue }
                let path = rel.isEmpty ? name : "\(rel)/\(name)"
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { rec(u, path); continue }
                let ext = u.pathExtension.lowercased()
                if Self.textExt.contains(ext) || name.range(of: "^[A-Z][A-Z._-]+$", options: .regularExpression) != nil || name.hasPrefix(".") { out.append(path) }
            }
        }
        rec(root, "")
        return out
    }
    func readTree(maxFiles: Int = 400, maxBytes: Int = 200_000) -> [String: String] {
        var out: [String: String] = [:]
        for p in walk(maxFiles: maxFiles) { if let s = try? String(contentsOf: url(p), encoding: .utf8), s.utf8.count <= maxBytes { out[p] = s } }
        return out
    }
    static func globRegex(_ pattern: String) -> NSRegularExpression? {
        var p = pattern.trimmingCharacters(in: .whitespaces); if p.hasPrefix("./") { p.removeFirst(2) }
        if !p.contains("/") && !p.hasPrefix("**") { p = "**/" + p }
        var re = ""
        var i = p.startIndex
        while i < p.endIndex {
            let c = p[i]
            if c == "*" {
                let n1 = p.index(after: i)
                if n1 < p.endIndex, p[n1] == "*" {
                    let n2 = p.index(after: n1)
                    if n2 < p.endIndex, p[n2] == "/" { re += "(?:.*/)?"; i = p.index(after: n2); continue }
                    re += ".*"; i = n2; continue
                }
                re += "[^/]*"
            } else if c == "?" { re += "." }
            else if "\\.+^$(){}|[]".contains(c) { re += "\\\(c)" }
            else { re.append(c) }
            i = p.index(after: i)
        }
        return try? NSRegularExpression(pattern: "^\(re)$")
    }
    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    func list(_ pattern: String?) -> String {
        var names = walk()
        if let pattern, !pattern.isEmpty, let re = Self.globRegex(pattern) { names = names.filter { Self.matches(re, $0) } }
        if names.isEmpty { return pattern == nil ? "(empty folder)" : "no files match" }
        return names.map { p in let n = (try? FileManager.default.attributesOfItem(atPath: url(p).path)[.size] as? Int) ?? 0; return "\(p) (\(n) bytes)" }.joined(separator: "\n")
    }
    static func numbered(_ text: String, offset: Int?, limit: Int?) -> String {
        let lines = text.components(separatedBy: "\n")
        let from = max(1, offset ?? 1), n = min(2000, max(1, limit ?? 2000))
        let slice = Array(lines.dropFirst(from - 1).prefix(n))
        let w = String(from + slice.count - 1).count
        var out = slice.enumerated().map { i, l in String(repeating: " ", count: max(0, w - String(from + i).count)) + "\(from + i)\t\(l)" }.joined(separator: "\n")
        if from - 1 + n < lines.count { out += "\n… \(lines.count - (from - 1 + n)) more lines (offset \(from + n))" }
        return out
    }
    func read(_ path: String, offset: Int?, limit: Int?) throws -> String {
        guard Self.okPath(path) else { throw ToolError("bad path") }
        guard let s = try? String(contentsOf: url(path), encoding: .utf8) else { throw ToolError("no such file: \(path)") }
        return Self.numbered(s, offset: offset, limit: limit)
    }
    func write(_ path: String, _ content: String) throws -> String {
        guard Self.okPath(path) else { throw ToolError("bad path") }
        let u = url(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: u, atomically: true, encoding: .utf8)
        return "wrote \(path) (\(content.utf8.count) bytes)"
    }
    func edit(_ path: String, old: String, new: String, all: Bool) throws -> (String, String) {
        guard Self.okPath(path) else { throw ToolError("bad path") }
        guard let s = try? String(contentsOf: url(path), encoding: .utf8) else { throw ToolError("no such file: \(path)") }
        guard !old.isEmpty else { throw ToolError("old_string is empty") }
        let n = s.components(separatedBy: old).count - 1
        guard n > 0 else { throw ToolError("old_string was not found in the file; read it again and copy the span exactly") }
        guard n == 1 || all else { throw ToolError("old_string occurs \(n) times; include more surrounding lines to make it unique, or set replace_all") }
        let next = all ? s.replacingOccurrences(of: old, with: new) : { var t = s; if let r = t.range(of: old) { t.replaceSubrange(r, with: new) }; return t }()
        try next.write(to: url(path), atomically: true, encoding: .utf8)
        return ("edited \(path): \(all ? n : 1) replacement\((all ? n : 1) > 1 ? "s" : "")", next)
    }
    func delete(_ path: String) throws -> String {
        guard Self.okPath(path), FileManager.default.fileExists(atPath: url(path).path) else { throw ToolError("no such file: \(path)") }
        try FileManager.default.removeItem(at: url(path)); return "deleted \(path)"
    }
    func search(_ pattern: String, glob: String?) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return "bad regular expression: \(pattern)" }
        let g = glob.flatMap { Self.globRegex($0) }
        var out: [String] = []
        for p in walk() {
            if let g, !Self.matches(g, p) { continue }
            guard let s = try? String(contentsOf: url(p), encoding: .utf8) else { continue }
            for (i, l) in s.components(separatedBy: "\n").enumerated() where out.count < 200 {
                if re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil { out.append("\(p):\(i + 1): \(l.prefix(240))") }
            }
            if out.count >= 200 { break }
        }
        return out.isEmpty ? "no matches" : out.joined(separator: "\n") + (out.count >= 200 ? "\n… more hits; narrow the pattern" : "")
    }
}
struct ToolError: LocalizedError { let message: String; init(_ m: String) { message = m }; var errorDescription: String? { message } }

/// a shell command in the folder, output streamed line by line; the login shell brings the member's PATH (nvm, cargo, anchor)
final class ShellRun: @unchecked Sendable {
    let process = Process()
    private let out = Pipe(), err = Pipe()
    private var buf = ["", ""]
    private let onLine: @Sendable (String) -> Void
    private var timer: DispatchWorkItem?
    init(root: URL, command: String, onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["FORCE_COLOR"] = "0"; env["CI"] = "1"; env["BROWSER"] = "none"; env["npm_config_fund"] = "false"; env["npm_config_audit"] = "false"; env["TERM"] = "dumb"
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.cargo/bin:\(NSHomeDirectory())/.local/share/solana/install/active_release/bin:\(NSHomeDirectory())/.avm/bin"
        process.environment = env
        process.standardOutput = out; process.standardError = err
        for (i, pipe) in [out, err].enumerated() {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let d = h.availableData; guard let self, !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
                self.feed(i, s)
            }
        }
    }
    private let lock = NSLock()
    private func feed(_ i: Int, _ s: String) {
        lock.lock(); buf[i] += s.replacingOccurrences(of: "\r", with: "\n"); var lines: [String] = []
        while let r = buf[i].firstIndex(of: "\n") { lines.append(String(buf[i][..<r])); buf[i] = String(buf[i][buf[i].index(after: r)...]) }
        lock.unlock()
        for l in lines { let c = Self.strip(l); if !c.trimmingCharacters(in: .whitespaces).isEmpty { onLine(c) } }
    }
    static func strip(_ s: String) -> String { s.replacingOccurrences(of: "\u{1b}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression) }
    /// runs to completion (or the timeout) and resolves with the exit code
    func run(timeout: TimeInterval) async -> (code: Int32?, timedOut: Bool) {
        await withCheckedContinuation { (cont: CheckedContinuation<(Int32?, Bool), Never>) in
            var done = false; let l = NSLock()
            let finish: (Int32?, Bool) -> Void = { c, t in l.lock(); defer { l.unlock() }; if done { return }; done = true; self.out.fileHandleForReading.readabilityHandler = nil; self.err.fileHandleForReading.readabilityHandler = nil
                for i in 0..<2 { let rest = Self.strip(self.buf[i]); if !rest.trimmingCharacters(in: .whitespaces).isEmpty { self.onLine(rest) } }
                cont.resume(returning: (c, t)) }
            process.terminationHandler = { p in finish(p.terminationStatus, false) }
            let t = DispatchWorkItem { [weak self] in guard let self, self.process.isRunning else { return }; self.onLine("[timed out after \(Int(timeout))s]"); self.process.terminate(); finish(nil, true) }
            timer = t
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: t)
            do { try process.run() } catch { onLine("[spawn error] \(error.localizedDescription)"); finish(nil, false) }
        }
    }
    func start() throws { try process.run() }
    func stop() { timer?.cancel(); if process.isRunning { process.terminate() } }
}
