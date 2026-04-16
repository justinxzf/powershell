import SwiftUI

struct NLInputBar: View {
    @Binding var inputText: String
    let nlRequest: NLRequest?
    let isConverting: Bool
    let onSubmit: (String) -> Void
    let onConfirmSuggestion: () -> Void
    let onEditSuggestion: () -> Void
    let onCancelSuggestion: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let request = nlRequest {
                switch request.status {
                case .converting:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在转换...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.05))

                case .suggested:
                    CommandSuggestionView(
                        request: request,
                        onConfirm: onConfirmSuggestion,
                        onEdit: onEditSuggestion,
                        onCancel: onCancelSuggestion
                    )

                case .error(let message):
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("取消") { onCancelSuggestion() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(12)

                default:
                    EmptyView()
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("输入命令或自然语言...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        let text = inputText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        onSubmit(text)
                        inputText = ""
                    }

                Button {
                    let text = inputText.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    onSubmit(text)
                    inputText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}
