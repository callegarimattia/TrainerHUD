import Foundation
import os

final class Log {
    static let shared = Log()
    private let logger = Logger(subsystem: "com.hugob.TrainerHUD", category: "app")
    private let queue = DispatchQueue(label: "log")
    private var handle: FileHandle?
    private(set) var lines: [String] = []
    var onAppend: ((String) -> Void)?
    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/TrainerHUD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("TrainerHUD.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
    }

    static func info(_ s: String) { shared.append("INFO", s) }
    static func warn(_ s: String) { shared.append("WARN", s) }
    static func error(_ s: String) { shared.append("ERR ", s) }
    static func ble(_ s: String) { shared.append("BLE ", s) }

    private func append(_ level: String, _ s: String) {
        let clean = String(s.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" }.map(Character.init))
        let line = "\(df.string(from: Date())) \(level) \(clean)"
        logger.log("\(line, privacy: .public)")
        queue.async {
            self.handle?.write((line + "\n").data(using: .utf8)!)
        }
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > 5000 { self.lines.removeFirst(1000) }
            self.onAppend?(line)
        }
    }
}
