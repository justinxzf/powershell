import Foundation

enum ShellHistoryParser {

    /// Returns unique single-line commands, newest first.
    /// Multi-line commands are dropped: writing their newlines to the PTY would execute them.
    static func parse(_ data: Data, shell: ShellType, limit: Int = 50, isTruncated: Bool = false) -> [String] {
        let bytes = shell == .zsh ? unmetafy(data) : Data(data)
        var lines = String(decoding: bytes, as: UTF8.self).components(separatedBy: "\n")
        if isTruncated, !lines.isEmpty { lines.removeFirst() }

        var commands: [String] = []
        var pending: String? = nil
        var pendingIsMultiline = false

        func flush() {
            if let cmd = pending, !pendingIsMultiline { commands.append(cmd) }
            pending = nil
            pendingIsMultiline = false
        }

        for rawLine in lines {
            if pending != nil {
                pendingIsMultiline = true
                pending! += "\n" + rawLine
                if !rawLine.hasSuffix("\\") { flush() }
                continue
            }

            var line = rawLine
            switch shell {
            case .zsh:
                if line.hasPrefix(": "), let semi = line.firstIndex(of: ";") {
                    line = String(line[line.index(after: semi)...])
                }
                if line.hasSuffix("\\") {
                    pending = line
                    continue
                }
            case .bash:
                if line.hasPrefix("#"), line.dropFirst().allSatisfy(\.isNumber), line.count > 1 {
                    continue
                }
            }
            pending = line
            flush()
        }
        flush()

        var seen = Set<String>()
        var result: [String] = []
        for cmd in commands.reversed() {
            let trimmed = cmd.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
            if result.count >= limit { break }
        }
        return result
    }

    /// zsh writes certain bytes as 0x83 (Meta) followed by the byte XOR 0x20.
    private static func unmetafy(_ data: Data) -> Data {
        var out = Data(capacity: data.count)
        var iterator = data.makeIterator()
        while let b = iterator.next() {
            if b == 0x83, let next = iterator.next() {
                out.append(next ^ 0x20)
            } else {
                out.append(b)
            }
        }
        return out
    }
}

enum ShellHistoryReader {
    private static let maxBytes: UInt64 = 256 * 1024

    static func historyFileURL(for shell: ShellType) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch shell {
        case .zsh: return home.appendingPathComponent(".zsh_history")
        case .bash: return home.appendingPathComponent(".bash_history")
        }
    }

    static func recentCommands(for shell: ShellType, limit: Int = 50) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: historyFileURL(for: shell)) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let offset = size > maxBytes ? size - maxBytes : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return [] }
        return ShellHistoryParser.parse(data, shell: shell, limit: limit, isTruncated: offset > 0)
    }
}
