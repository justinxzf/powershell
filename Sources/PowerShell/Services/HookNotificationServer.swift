import Foundation
import Network

@MainActor
final class HookNotificationServer {
    static let shared = HookNotificationServer()

    private var listener: NWListener?
    private(set) var activePort: UInt16?
    private let basePort: UInt16 = 9786
    private let maxPortOffset: UInt16 = 10

    var onHookNotification: ((HookEvent) -> Void)?

    var port: UInt16 { activePort ?? basePort }

    private static let portFileURL: URL = {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".powershell/hook-port")
    }()

    func start() {
        if listener != nil, activePort != nil {
            DebugLog.write("[HookServer] already running on port \(activePort!)")
            return
        }

        for offset in 0...maxPortOffset {
            let candidatePort = basePort + offset
            if isPortAvailable(candidatePort) {
                DebugLog.write("[HookServer] trying port \(candidatePort)...")
                bindAndStart(port: candidatePort)
                return
            }
            DebugLog.write("[HookServer] port \(candidatePort) is in use, skipping")
        }
        DebugLog.write("[HookServer] all ports \(basePort)-\(basePort + maxPortOffset) are in use, hook server not started")
    }

    private func isPortAvailable(_ port: UInt16) -> Bool {
        // Quick TCP check: try connecting to the port
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected != 0 // connection failed = port is free
    }

    private func bindAndStart(port candidatePort: UInt16) {
        do {
            let params = NWParameters.tcp
            let nwListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: candidatePort)!)
            let server = self

            nwListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    DebugLog.write("[HookServer] listener ready on port \(candidatePort)")
                case .failed(let err):
                    DebugLog.write("[HookServer] listener on port \(candidatePort) failed: \(err)")
                    Task { @MainActor in
                        if server.activePort == candidatePort {
                            server.listener = nil
                            server.activePort = nil
                            server.writePortFile(nil)
                        }
                    }
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { conn in
                DebugLog.write("[HookServer] new connection from \(conn.endpoint)")
                Task { @MainActor in
                    server.handleConnection(conn)
                }
            }

            nwListener.start(queue: .main)
            self.listener = nwListener
            self.activePort = candidatePort
            writePortFile(candidatePort)
            DebugLog.write("[HookServer] started on port \(candidatePort)")
        } catch {
            DebugLog.write("[HookServer] port \(candidatePort) bind error: \(error)")
            writePortFile(nil)
        }
    }

    private func writePortFile(_ port: UInt16?) {
        let url = Self.portFileURL
        if let port {
            try? "\(port)".write(to: url, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .main)
        let server = self
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, context, isComplete, error in
            if let error {
                DebugLog.write("[HookServer] receive error: \(error)")
                self.sendResponse(conn)
                return
            }
            guard let data = content else {
                DebugLog.write("[HookServer] received nil content (isComplete=\(isComplete))")
                self.sendResponse(conn)
                return
            }
            DebugLog.write("[HookServer] received \(data.count) bytes, isComplete=\(isComplete)")
            let body = server.extractBody(from: data)
            DebugLog.write("[HookServer] body size: \(body.count), preview: \(String(data: body.prefix(200), encoding: .utf8) ?? "<non-utf8>")")
            server.processBody(body)
            self.sendResponse(conn)
        }
    }

    nonisolated private func sendResponse(_ conn: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        let responseData = response.data(using: .utf8)!
        conn.send(content: responseData, completion: .contentProcessed { _ in })
    }

    nonisolated private func extractBody(from data: Data) -> Data {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return data }
        let bodyStart = headerEnd.upperBound
        guard bodyStart < data.count else { return Data() }
        return data[bodyStart...]
    }

    nonisolated private func processBody(_ body: Data) {
        if body.isEmpty {
            DebugLog.write("[HookServer] empty body, skipping")
            return
        }
        guard let event = try? JSONDecoder().decode(HookEvent.self, from: body) else {
            DebugLog.write("[HookServer] JSON decode failed, trying text fallback")
            if let text = String(data: body, encoding: .utf8), !text.isEmpty {
                let fallback = HookEvent(
                    hook_event_name: "notification",
                    notification_type: nil,
                    message: text,
                    title: nil,
                    session_id: nil,
                    cwd: nil,
                    last_assistant_message: nil
                )
                DebugLog.write("[HookServer] fallback event: \(fallback.hook_event_name)")
                Task { @MainActor in
                    onHookNotification?(fallback)
                }
            }
            return
        }
        DebugLog.write("[HookServer] decoded event: \(event.hook_event_name), session_id=\(event.session_id ?? "nil"), type=\(event.notification_type ?? "nil")")
        Task { @MainActor in
            onHookNotification?(event)
        }
    }
}

struct HookEvent: Codable, Sendable {
    let hook_event_name: String
    let notification_type: String?
    let message: String?
    let title: String?
    let session_id: String?
    let cwd: String?
    let last_assistant_message: String?

    var displayTitle: String {
        switch notification_type ?? hook_event_name {
        case "permission_prompt": return "权限请求"
        case "idle_prompt": return "等待输入"
        case "auth_success": return "授权成功"
        case "elicitation_dialog": return "用户交互"
        case "Stop", "stop": return "任务完成"
        default: return "Claude Code"
        }
    }

    var displayMessage: String {
        if let msg = message, !msg.isEmpty { return msg }
        if let msg = last_assistant_message, !msg.isEmpty {
            return msg.count > 100 ? String(msg.prefix(100)) + "..." : msg
        }
        switch notification_type ?? hook_event_name {
        case "permission_prompt": return "Claude 需要你的权限批准"
        case "idle_prompt": return "Claude 正在等待你的输入"
        case "auth_success": return "授权已通过"
        case "elicitation_dialog": return "Claude 需要你的交互"
        case "Stop", "stop": return "Claude Code 已完成任务"
        default: return "Claude Code 通知"
        }
    }
}
