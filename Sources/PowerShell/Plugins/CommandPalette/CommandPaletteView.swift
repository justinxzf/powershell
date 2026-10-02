import SwiftUI

/// Always present in the overlay stack; observes the concrete plugin directly so
/// open/close state changes re-render without depending on the parent view.
struct CommandPaletteOverlay: View {
    let plugin: CommandPalettePlugin
    let size: CGSize

    var body: some View {
        if plugin.openSessionId != nil {
            ZStack(alignment: .top) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { plugin.close() }

                CommandPalettePanel(plugin: plugin)
                    .frame(width: min(520, max(size.width - 40, 200)))
                    .frame(maxHeight: min(420, max(size.height - 100, 160)))
                    .padding(.top, 48)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

private struct CommandPalettePanel: View {
    @Bindable var plugin: CommandPalettePlugin
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = plugin.items
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索命令", text: $plugin.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if items.isEmpty {
                Text(plugin.query.isEmpty ? "暂无命令" : "没有匹配的命令")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                list(items)
            }

            Divider()

            Text("↑↓ 选择 · ↩ 写入终端 · esc 关闭")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private func list(_ items: [PaletteItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || items[index - 1].kind != item.kind {
                            sectionHeader(item.kind)
                        }
                        PaletteRow(
                            item: item,
                            isSelected: index == plugin.selectedIndex,
                            onHover: { plugin.selectedIndex = index },
                            onTap: { plugin.commit(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)
            .onChange(of: plugin.selectedIndex) { _, newValue in
                guard items.indices.contains(newValue) else { return }
                proxy.scrollTo(items[newValue].id)
            }
        }
    }

    private func sectionHeader(_ kind: PaletteItem.Kind) -> some View {
        Text(kind == .preset ? "预设命令" : "最近命令")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool
    let onHover: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind == .preset ? "star" : "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                .frame(width: 14)
            Text(item.text)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { if $0 { onHover() } }
        .onTapGesture(perform: onTap)
    }
}
