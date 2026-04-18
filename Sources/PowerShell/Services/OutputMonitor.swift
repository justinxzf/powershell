import Foundation

enum AttentionType: Sendable {
    case oscNotification(title: String, body: String)
}

@MainActor
final class OutputMonitor {
    var onAttentionNeeded: ((AttentionType) -> Void)?

    private var cooldownUntil: Date = .distantPast
    private let cooldownInterval: TimeInterval = 2.0

    // Partial match state for scanning OSC sequences across slices
    private var pendingBytes = Data()

    /// Only detect OSC 9 notifications (\x1b]9;<message>\x07).
    /// These are emitted by Claude Code hooks configured in settings.
    func processOutput(slice: ArraySlice<UInt8>) {
        let data = pendingBytes + Data(slice)
        pendingBytes.removeAll(keepingCapacity: true)

        // Scan for OSC 9: \x1b]9;<message>ST  (ST = BEL or ESC \)
        if let msg = extractOSC9(from: data) {
            trigger(.oscNotification(title: "Claude Code", body: msg))
            pendingBytes.removeAll(keepingCapacity: true)
            return
        }

        // Keep trailing bytes that might be start of an incomplete OSC sequence
        if data.count > 2 {
            let tailLen = min(data.count, 32)
            let tail = data.suffix(tailLen)
            if tail.contains(0x1b) {
                pendingBytes = Data(tail)
            }
        }
    }

    func reset() {
        pendingBytes.removeAll(keepingCapacity: true)
    }

    // MARK: - OSC Parsing

    /// Extract OSC 9 message: \x1b]9;<message>\x07 or \x1b]9;<message>\x1b\\
    private func extractOSC9(from data: Data) -> String? {
        let pattern: [UInt8] = [0x1b, 0x5d, 0x39, 0x3b] // ESC ] 9 ;
        guard let range = data.range(of: Data(pattern)) else { return nil }

        let msgStart = range.upperBound
        let msgEnd = findTerminator(in: data, after: msgStart)
        guard msgStart < msgEnd else { return nil }
        let msgData = data[msgStart..<msgEnd]
        return String(data: msgData, encoding: .utf8)
    }

    /// Find BEL (0x07) or ST (ESC \) terminator after given position
    private func findTerminator(in data: Data, after start: Int) -> Int {
        for i in start..<data.count {
            if data[i] == 0x07 { return i }
            if data[i] == 0x1b && i + 1 < data.count && data[i + 1] == 0x5c { return i }
        }
        return data.count
    }

    private func trigger(_ type: AttentionType) {
        guard Date() >= cooldownUntil else { return }
        cooldownUntil = Date().addingTimeInterval(cooldownInterval)
        onAttentionNeeded?(type)
    }
}
