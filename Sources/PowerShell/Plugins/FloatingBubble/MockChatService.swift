import Foundation

@MainActor
final class MockChatService {
    private let responses: [String] = [
        "我正在思考中... 试试用 Cmd+K 来快速清屏！",
        "你知道吗？可以用 Ctrl+R 搜索命令历史哦。",
        "建议试试 `git log --oneline --graph` 查看提交树。",
        "PowerShell 小贴士：拖拽文件到终端可以自动填入路径。",
        "需要分屏？试试侧边栏的分屏按钮。",
        "如果终端卡住了，试试 Ctrl+C 中断当前命令。",
        "推荐使用 `alias` 定义常用命令的缩写。",
        "你可以用 `!!` 重复上一条命令哦。",
    ]

    func reply(to message: String) async -> String {
        try? await Task.sleep(for: .milliseconds(500))
        return responses.randomElement() ?? "收到！"
    }
}
