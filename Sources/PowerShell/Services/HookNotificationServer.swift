import Foundation
import Network

@MainActor
final class HookNotificationServer {
    static let shared = HookNotificationServer()

    private var listener: NWListener?
    let port: UInt16 = 9786

    var onHookNotification: ((HookEvent) -> Void)?

    func start() {
        do {
            let params = NWParameters.tcp
            let nwListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            nwListener.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    print("HookNotificationServer listener failed: \(err)")
                }
            }
            let server = self
            nwListener.newConnectionHandler = { conn in
                Task { @MainActor in
                    server.handleConnection(conn)
                }
            }
            nwListener.start(queue: .main)
            self.listener = nwListener
        } catch {
            print("HookNotificationServer failed to start: \(error)")
        }
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .main)
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 65536, alignment: 8)
        let server = self
        conn.receive(minimumIncompleteLength: 1, maximumLength: buffer.count) { content, _, _, _ in
            let body: Data
            if let data = content {
                body = server.extractBody(from: data)
                server.processBody(body)
            }

            let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
            let responseData = response.data(using: .utf8)!
            conn.send(content: responseData, completion: .contentProcessed { _ in })
            buffer.deallocate()
        }
    }

    nonisolated private func extractBody(from data: Data) -> Data {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return data }
        let bodyStart = headerEnd.upperBound
        guard bodyStart < data.count else { return Data() }
        return data[bodyStart...]
    }

    nonisolated private func processBody(_ body: Data) {
        guard let event = try? JSONDecoder().decode(HookEvent.self, from: body) else {
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
                Task { @MainActor in
                    onHookNotification?(fallback)
                }
            }
            return
        }
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
