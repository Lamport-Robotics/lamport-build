import Foundation
import Darwin

/// the coding engine that ships inside the app: one local server for every folder, reached over http, server-sent events and a websocket per terminal
@MainActor
final class Engine: ObservableObject {
    enum State: Equatable { case starting, ready, failed(String) }
    @Published private(set) var state: State = .starting

    /// the names the bundled engine expects on the wire; they travel with the binary in engine.json
    struct Wire: Decodable { let user: String; let passwordEnv: String; let ticketHeader: String }
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    private(set) var base = URL(string: "http://127.0.0.1")!
    private var auth = ""
    private var ticketHeader = ""
    private var proc: Process?
    private let stream: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60 * 60 * 24
        c.timeoutIntervalForResource = 60 * 60 * 24 * 7
        return URLSession(configuration: c)
    }()

    /// `--engine <dir>` in development, the bundle's engine folder in a release
    static var dir: URL? {
        if let i = CommandLine.arguments.firstIndex(of: "--engine"), i + 1 < CommandLine.arguments.count { return URL(fileURLWithPath: CommandLine.arguments[i + 1]) }
        return Bundle.main.resourceURL?.appendingPathComponent("engine")
    }
    /// the engine keeps its config, sessions and caches here, apart from anything else on the Mac
    static let home = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lamport Build/engine", isDirectory: true)

    /// the last engine this app started; one left over from a crash or a kill is stopped before a new one starts
    static let pidFile = home.appendingPathComponent("engine.pid")

    func start() async {
        Engine.reap()
        guard let dir = Engine.dir,
              let data = try? Data(contentsOf: dir.appendingPathComponent("engine.json")),
              let wire = try? JSONDecoder().decode(Wire.self, from: data) else { state = .failed("The engine is missing from this build."); return }
        let port = Engine.freePort()
        let password = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        let p = Process()
        p.executableURL = dir.appendingPathComponent("lamport-engine")
        p.arguments = ["serve", "--hostname", "127.0.0.1", "--port", String(port)]
        var env = ProcessInfo.processInfo.environment
        env[wire.passwordEnv] = password
        for (key, sub) in [("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"), ("XDG_STATE_HOME", "state"), ("XDG_CACHE_HOME", "cache")] {
            let u = Engine.home.appendingPathComponent(sub, isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            env[key] = u.path
        }
        p.environment = env
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let out = Pipe()
        p.standardOutput = out; p.standardError = out
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty, let s = String(data: d, encoding: .utf8) { Log.write("engine " + s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        p.terminationHandler = { [weak self] pr in
            Task { @MainActor in self?.state = .failed("The engine stopped (exit \(pr.terminationStatus)).") }
        }
        do { try p.run() } catch { state = .failed("Could not start the engine: \(error.localizedDescription)"); return }
        proc = p
        try? String(p.processIdentifier).write(to: Engine.pidFile, atomically: true, encoding: .utf8)
        base = URL(string: "http://127.0.0.1:\(port)")!
        auth = "Basic " + Data("\(wire.user):\(password)".utf8).base64EncodedString()
        ticketHeader = wire.ticketHeader
        for _ in 0..<120 {
            if (try? await call("/api/info")) != nil { state = .ready; Log.write("engine ready on \(port)"); return }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        state = .failed("The engine did not answer.")
    }

    func stop() {
        proc?.terminationHandler = nil
        proc?.terminate()
        proc = nil
        try? FileManager.default.removeItem(at: Engine.pidFile)
    }

    /// stop an engine a previous run of the app left behind, but only if that pid really is our engine
    nonisolated static func reap() {
        guard let s = try? String(contentsOf: pidFile, encoding: .utf8), let pid = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf).hasSuffix("/lamport-engine") {
            kill(pid, SIGTERM)
            Log.write("stopped a leftover engine \(pid)")
        }
        try? FileManager.default.removeItem(at: pidFile)
    }

    // MARK: http

    func request(_ path: String, method: String = "GET", query: [(String, String)] = [], json: Any? = nil) -> URLRequest {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        var r = URLRequest(url: c.url!)
        r.httpMethod = method
        r.setValue(auth, forHTTPHeaderField: "Authorization")
        if let json {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        return r
    }

    /// one call, the decoded body back (nil for an empty 2xx)
    @discardableResult
    func call(_ path: String, method: String = "GET", query: [(String, String)] = [], json: Any? = nil, headers: [String: String] = [:]) async throws -> Any? {
        var r = request(path, method: method, query: query, json: json)
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
        if status >= 400 { throw Failure(message: (obj as? [String: Any])?["message"] as? String ?? "The engine answered \(status).") }
        return obj
    }

    /// the `data` field most endpoints wrap their answer in
    func data(_ path: String, method: String = "GET", query: [(String, String)] = [], json: Any? = nil) async throws -> Any? {
        (try await call(path, method: method, query: query, json: json) as? [String: Any])?["data"]
    }

    /// every event the engine emits, for all folders and sessions, until the stream drops
    func events() -> AsyncThrowingStream<[String: Any], Error> {
        let r = request("/api/event")
        let session = stream
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    let (bytes, resp) = try await session.bytes(for: r)
                    if let s = (resp as? HTTPURLResponse)?.statusCode, s >= 400 { throw Failure(message: "The event stream answered \(s).") }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let body = line.dropFirst(5).drop(while: { $0 == " " })
                        if let d = body.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { cont.yield(obj) }
                    }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: terminals

    /// a shell in `directory`, and the websocket address to attach to it
    func openTerminal(in directory: String, cols: Int, rows: Int) async throws -> (id: String, url: URL) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let made = try await data("/api/pty", method: "POST", query: [("location[directory]", directory)], json: [
            "command": shell, "args": ["-l"], "cwd": directory, "title": URL(fileURLWithPath: directory).lastPathComponent,
            "env": ["TERM": "xterm-256color", "COLORTERM": "truecolor"],
        ]) as? [String: Any]
        guard let id = made?["id"] as? String else { throw Failure(message: "The engine did not open a terminal.") }
        try? await resizeTerminal(id, directory: directory, cols: cols, rows: rows)
        return (id, try await terminalURL(id, directory: directory))
    }

    func terminalURL(_ id: String, directory: String) async throws -> URL {
        let t = try await call("/api/pty/\(id)/connect-token", method: "POST", query: [("location[directory]", directory)], headers: [ticketHeader: "1"]) as? [String: Any]
        guard let ticket = (t?["data"] as? [String: Any])?["ticket"] as? String else { throw Failure(message: "The engine refused the terminal.") }
        var c = URLComponents(url: base.appendingPathComponent("/api/pty/\(id)/connect"), resolvingAgainstBaseURL: false)!
        c.scheme = "ws"
        c.queryItems = [URLQueryItem(name: "location[directory]", value: directory), URLQueryItem(name: "ticket", value: ticket)]
        return c.url!
    }

    func resizeTerminal(_ id: String, directory: String, cols: Int, rows: Int) async throws {
        try await call("/api/pty/\(id)", method: "PUT", query: [("location[directory]", directory)], json: ["size": ["cols": max(cols, 1), "rows": max(rows, 1)]])
    }

    func closeTerminal(_ id: String, directory: String) async {
        _ = try? await call("/api/pty/\(id)", method: "DELETE", query: [("location[directory]", directory)])
    }

    // MARK: helpers

    /// a port nothing on this Mac is listening on right now
    static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        let port = Int(UInt16(bigEndian: addr.sin_port))
        return port == 0 ? 47_000 + Int.random(in: 0..<2000) : port
    }
}
