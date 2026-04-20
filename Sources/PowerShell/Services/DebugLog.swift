import Foundation

enum DebugLog {
    private static let logDir: URL = {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".powershell/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let logFile: URL = logDir.appendingPathComponent("debug.log")

    private static let queue = DispatchQueue(label: "com.powershell.debuglog")

    static func write(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        print(line)
        queue.async {
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
        }
    }

    static func rotateIfNeeded() {
        queue.sync {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
                  let size = attrs[.size] as? UInt64, size > 5 * 1024 * 1024 else { return }
            let backup = logDir.appendingPathComponent("debug-prev.log")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: logFile, to: backup)
        }
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}
