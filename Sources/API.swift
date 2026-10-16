import Foundation

/// lamport.si from the app: the same routes the web desk uses, signed with the app's own token
struct API {
    static var base: URL {
        if let i = CommandLine.arguments.firstIndex(of: "--api"), i + 1 < CommandLine.arguments.count, let u = URL(string: CommandLine.arguments[i + 1]) { return u }
        if let s = UserDefaults.standard.string(forKey: "apiBase"), let u = URL(string: s) { return u }
        return URL(string: "https://lamport.si")!
    }
    static var isLocalDev: Bool { base.host == "localhost" || base.host == "127.0.0.1" }
    static var token: String? { Keychain.get("appToken") }

    static func request(_ path: String, method: String = "GET", json: Any? = nil) -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("Lamport Build for Mac/0.1", forHTTPHeaderField: "User-Agent")
        if let t = token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        else if isLocalDev { r.setValue("dev", forHTTPHeaderField: "x-dev-user") }
        if let json {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        return r
    }
    struct HTTPError: LocalizedError { let status: Int; let message: String; var errorDescription: String? { message } }
    static func call(_ path: String, method: String = "GET", json: Any? = nil) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: request(path, method: method, json: json))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status >= 400 { throw HTTPError(status: status, message: obj["error"] as? String ?? "error \(status)") }
        return obj
    }
    /// server-sent events as a stream of decoded json objects
    static func events(_ path: String, json: Any) -> AsyncThrowingStream<[String: Any], Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: request(path, method: "POST", json: json))
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if status >= 400 {
                        var body = Data(); for try await b in bytes { body.append(b) }
                        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                        throw HTTPError(status: status, message: obj?["error"] as? String ?? "error \(status)")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        if let d = line.dropFirst(6).data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { cont.yield(obj) }
                    }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
    /// the website, for sign-in and the workspace; in local development the web dev server sits on its own port
    static func siteURL(_ path: String) -> URL { (isLocalDev ? URL(string: "http://localhost:5190")! : base).appendingPathComponent(path) }
}
