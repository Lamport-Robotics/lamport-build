import Foundation

/// the local run: npm install, then the dev or start script, in the project folder; the first localhost url becomes the preview
@MainActor
final class LocalRuntime: ObservableObject {
    enum Status: String { case idle, installing, starting, running, exited, failed }
    @Published var status: Status = .idle
    @Published var url: URL? = nil
    @Published var log: [String] = []
    @Published var exitCode: Int32? = nil
    @Published var error: String? = nil
    @Published var command: String? = nil
    private var child: ShellRun? = nil
    private var generation = 0

    func line(_ l: String) {
        log.append(l); if log.count > 600 { log.removeFirst(log.count - 600) }
        if url == nil, let r = l.range(of: #"https?://(localhost|127\.0\.0\.1)(:\d+)?[^\s]*"#, options: .regularExpression) {
            var s = String(l[r]).replacingOccurrences(of: "127.0.0.1", with: "localhost")
            while let last = s.last, ".,;)]".contains(last) { s.removeLast() }
            if let u = URL(string: s) { url = u; status = .running }
        }
    }
    func run(root: URL, files: [String: String]) async {
        await stop()
        generation += 1; let gen = generation
        status = .installing; url = nil; log = []; exitCode = nil; error = nil; command = "npm install"
        var scripts: [String: Any] = [:]
        if let pkg = files["package.json"]?.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: pkg)) as? [String: Any] { scripts = obj["scripts"] as? [String: Any] ?? [:] }
        let script = scripts["dev"] != nil ? "dev" : scripts["start"] != nil ? "start" : scripts["build"] != nil ? "build" : nil
        line("$ npm install")
        let inst = ShellRun(root: root, command: "npm install --no-audit --no-fund --loglevel=error") { [weak self] l in Task { @MainActor in self?.line(l) } }
        let r = await inst.run(timeout: 600)
        guard gen == generation else { return }
        if r.code != 0 { status = .failed; exitCode = r.code; error = "npm install exited with \(r.code.map(String.init) ?? "?")"; return }
        guard let script else { status = .exited; exitCode = 0; line("no dev/start/build script in package.json"); return }
        status = .starting; command = "npm run \(script)"; line("$ npm run \(script)")
        let dev = ShellRun(root: root, command: "npm run \(script)") { [weak self] l in Task { @MainActor in self?.line(l) } }
        dev.process.terminationHandler = { [weak self] p in Task { @MainActor in guard let self, self.generation == gen else { return }; self.child = nil; self.exitCode = p.terminationStatus; self.status = p.terminationStatus == 0 ? .exited : .failed; self.error = p.terminationStatus == 0 ? nil : "npm run \(script) exited with \(p.terminationStatus)" } }
        child = dev
        do { try dev.start() } catch { status = .failed; self.error = error.localizedDescription }
    }
    func stop() async {
        generation += 1
        if let c = child { child = nil; c.stop() }
        if status == .running || status == .starting || status == .installing { status = .idle }
    }
    func errorReport() -> String {
        let i = log.firstIndex { $0.range(of: "error|ERR!|failed|cannot find|not found|SyntaxError|TypeError", options: [.regularExpression, .caseInsensitive]) != nil }
        let tail = (i.map { Array(log[max(0, $0 - 3)...]) } ?? log).suffix(60)
        return "\(command ?? "the run") \(error ?? "failed").\n\nTerminal output:\n\(tail.joined(separator: "\n"))"
    }
}
