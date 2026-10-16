import Foundation

/// a plain support log in ~/Library/Logs/Lamport Build/app.log, rotated at 2 MB; no telemetry leaves the Mac
enum Log {
    static let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Lamport Build", isDirectory: true)
    static let file = dir.appendingPathComponent("app.log")
    private static let q = DispatchQueue(label: "si.lamport.build.log")
    static func write(_ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        q.async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int, size > 2_000_000 { try? FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("app.1.log")) }
            if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? line.write(to: file, atomically: true, encoding: .utf8) }
        }
    }
}
