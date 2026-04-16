import SwiftUI

struct CommandSuggestionView: View {
    let request: NLRequest
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("检测到自然语言")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Spacer()
                if request.isDangerous {
                    Label("危险命令", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Text(request.input)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let command = request.suggestedCommand {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(request.isDangerous ? Color.red : Color.blue.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack(spacing: 8) {
                Button("确认执行 (↵)") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(request.isDangerous ? .red : .blue)

                Button("编辑命令") { onEdit() }
                    .buttonStyle(.bordered)

                Button("取消 (Esc)") { onCancel() }
                    .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
