import SwiftUI

struct CommandSuggestionView: View {
    let request: NLRequest
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void
    var darkStyle: Bool = false

    private var accentColor: Color { darkStyle ? .cyan : .blue }
    private var inputColor: Color { darkStyle ? .white.opacity(0.7) : .secondary }
    private var commandTextColor: Color { darkStyle ? .white : .primary }
    private var commandBg: Color { darkStyle ? .white.opacity(0.1) : Color(nsColor: .textBackgroundColor) }
    private var cardBg: Color { darkStyle ? .black.opacity(0.9) : .blue.opacity(0.05) }
    private var cardBorder: Color { darkStyle ? .cyan.opacity(0.3) : .clear }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            Text(request.input)
                .font(.callout)
                .foregroundStyle(inputColor)

            if let command = request.suggestedCommand {
                commandView(command)
            }

            actionButtons
        }
        .padding(12)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(accentColor)
            Text("检测到自然语言")
                .font(.caption)
                .foregroundStyle(accentColor)
            Spacer()
            if request.isDangerous {
                Label("危险命令", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func commandView(_ command: String) -> some View {
        Text(command)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(commandTextColor)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(commandBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(commandBorderColor, lineWidth: 1)
            )
    }

    private var commandBorderColor: Color {
        if request.isDangerous { return .red }
        return darkStyle ? .cyan.opacity(0.5) : .blue.opacity(0.3)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button("确认执行 (↵)") { onConfirm() }
                .buttonStyle(.borderedProminent)
                .tint(request.isDangerous ? .red : accentColor)

            Button("编辑命令") { onEdit() }
                .buttonStyle(.bordered)

            Button("取消 (Esc)") { onCancel() }
                .buttonStyle(.bordered)

            Spacer()
        }
    }
}
