import SwiftUI

// MARK: - Split Role

enum SplitRole {
    case singlePane
    case hPrimary(secondaryId: UUID)
    case vPrimary(secondaryId: UUID)
    case gridControl
    case secondary
}

// MARK: - SplitPlugin

@Observable
@MainActor
final class SplitPlugin: PowerShellPlugin {

    let pluginId = "com.powershell.split"

    var splitLayout: SplitLayout? = nil
    var splitHRatio: Double = 0.5
    var splitVRatio: Double = 0.5
    private var storedSplitLayout: SplitLayout? = nil
    var pendingGridSlot1: UUID? = nil

    func setup() {
        PluginManager.shared.registerSplitPlugin(self)
    }

    // MARK: - Split Operations

    func splitHorizontal(left: UUID, right: UUID) {
        storedSplitLayout = nil
        splitLayout = .horizontal(left: left, right: right)
        splitHRatio = 0.5
        pendingGridSlot1 = nil
    }

    func splitVertical(top: UUID, bottom: UUID) {
        storedSplitLayout = nil
        splitLayout = .vertical(top: top, bottom: bottom)
        splitVRatio = 0.5
        pendingGridSlot1 = nil
    }

    func splitGrid(topLeft: UUID, topRight: UUID, bottomLeft: UUID, bottomRight: UUID) {
        storedSplitLayout = nil
        splitLayout = .grid(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
        splitHRatio = 0.5
        splitVRatio = 0.5
        pendingGridSlot1 = nil
    }

    func unsplit() {
        storedSplitLayout = nil
        splitLayout = nil
        pendingGridSlot1 = nil
    }

    // MARK: - Layout Helpers

    func isPrimary(sessionId: UUID) -> Bool {
        switch splitLayout {
        case .horizontal(let l, _): return l == sessionId
        case .vertical(let t, _): return t == sessionId
        case .grid(let tl, _, _, _): return tl == sessionId
        default: return false
        }
    }

    func paneFrame(for sessionId: UUID, W: CGFloat, H: CGFloat) -> CGRect? {
        let hr = splitHRatio
        let vr = splitVRatio
        switch splitLayout {
        case .horizontal(let l, let r):
            if sessionId == l { return CGRect(x: 0,    y: 0, width: W * hr,      height: H) }
            if sessionId == r { return CGRect(x: W * hr, y: 0, width: W * (1 - hr), height: H) }
        case .vertical(let t, let b):
            if sessionId == t { return CGRect(x: 0, y: 0,      width: W, height: H * vr) }
            if sessionId == b { return CGRect(x: 0, y: H * vr, width: W, height: H * (1 - vr)) }
        case .grid(let tl, let tr, let bl, let br):
            if sessionId == tl { return CGRect(x: 0,      y: 0,      width: W * hr,      height: H * vr) }
            if sessionId == tr { return CGRect(x: W * hr, y: 0,      width: W * (1 - hr), height: H * vr) }
            if sessionId == bl { return CGRect(x: 0,      y: H * vr, width: W * hr,      height: H * (1 - vr)) }
            if sessionId == br { return CGRect(x: W * hr, y: H * vr, width: W * (1 - hr), height: H * (1 - vr)) }
        case .none:
            return nil
        }
        return nil
    }

    func role(of sessionId: UUID) -> SplitRole {
        switch splitLayout {
        case .horizontal(let l, let r):
            if sessionId == l { return .hPrimary(secondaryId: r) }
            if sessionId == r { return .secondary }
        case .vertical(let t, let b):
            if sessionId == t { return .vPrimary(secondaryId: b) }
            if sessionId == b { return .secondary }
        case .grid(let tl, _, _, _):
            if sessionId == tl { return .gridControl }
            if splitLayout!.contains(sessionId) { return .secondary }
        case .none:
            break
        }
        return .singlePane
    }

    // MARK: - Plugin Hooks

    func sessionDidActivate(sessionId: UUID) {
        if let layout = splitLayout {
            if !layout.contains(sessionId) {
                storedSplitLayout = layout
                splitLayout = nil
            }
        } else if let stored = storedSplitLayout, stored.contains(sessionId) {
            splitLayout = stored
            storedSplitLayout = nil
        }
    }

    func sessionWillDelete(sessionId: UUID) {
        if let layout = splitLayout, layout.contains(sessionId) { unsplit() }
        if let stored = storedSplitLayout, stored.contains(sessionId) { storedSplitLayout = nil }
    }

    func overlayView(size: CGSize) -> AnyView? {
        guard splitLayout != nil else { return nil }
        return AnyView(SplitOverlayView(plugin: self, size: size))
    }

    func headerAccessoryView(for session: Session, allSessions: [Session]) -> AnyView? {
        AnyView(SplitHeaderAccessoryView(plugin: self, session: session, allSessions: allSessions))
    }
}

// MARK: - Split Overlay (分割线)

struct SplitOverlayView: View {
    @Bindable var plugin: SplitPlugin
    let size: CGSize

    var body: some View {
        switch plugin.splitLayout {
        case .horizontal:
            SplitDividerView(axis: .vertical, ratio: $plugin.splitHRatio, totalSize: size.width)
        case .vertical:
            SplitDividerView(axis: .horizontal, ratio: $plugin.splitVRatio, totalSize: size.height)
        case .grid:
            SplitDividerView(axis: .vertical,   ratio: $plugin.splitHRatio, totalSize: size.width)
            SplitDividerView(axis: .horizontal, ratio: $plugin.splitVRatio, totalSize: size.height)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Split Header Accessory (header 控件)

struct SplitHeaderAccessoryView: View {
    let plugin: SplitPlugin
    let session: Session
    let allSessions: [Session]

    private var availableSessions: [Session] {
        let excluded: Set<UUID> = {
            var ids: Set<UUID> = [session.id]
            switch plugin.splitLayout {
            case .horizontal(let l, let r): ids.insert(l); ids.insert(r)
            case .vertical(let t, let b): ids.insert(t); ids.insert(b)
            case .grid(let tl, let tr, let bl, let br): ids.formUnion([tl, tr, bl, br])
            case .none: break
            }
            return ids
        }()
        return allSessions.filter { !excluded.contains($0.id) }
    }

    var body: some View {
        switch plugin.role(of: session.id) {
        case .singlePane:
            splitMenuView
        case .hPrimary(let secId):
            splitSummaryView(secondaryId: secId, isVertical: false)
        case .vPrimary(let secId):
            splitSummaryView(secondaryId: secId, isVertical: true)
        case .gridControl:
            unsplitButton
        case .secondary:
            EmptyView()
        }
    }

    // 单窗格分屏按钮：水平和垂直各一个
    @ViewBuilder
    private var splitMenuView: some View {
        splitDirectionButton(horizontal: true)
        splitDirectionButton(horizontal: false)
    }

    @ViewBuilder
    private func splitDirectionButton(horizontal: Bool) -> some View {
        let others = allSessions.filter { $0.id != session.id }
        let icon = horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2"
        let help = horizontal ? "左右分屏" : "上下分屏"

        if others.isEmpty {
            EmptyView()
        } else if others.count == 1, let other = others.first {
            Button {
                if horizontal {
                    plugin.splitHorizontal(left: session.id, right: other.id)
                } else {
                    plugin.splitVertical(top: session.id, bottom: other.id)
                }
            } label: {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(help)
        } else {
            Menu {
                ForEach(others, id: \.id) { s in
                    Button(s.name) {
                        if horizontal {
                            plugin.splitHorizontal(left: session.id, right: s.id)
                        } else {
                            plugin.splitVertical(top: session.id, bottom: s.id)
                        }
                    }
                }
            } label: {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(help)
        }
    }

    // 两窗格分屏时 primary 的 summary：名称 + 取消 + 扩展四宫格
    @ViewBuilder
    private func splitSummaryView(secondaryId: UUID, isVertical: Bool) -> some View {
        let secName = allSessions.first(where: { $0.id == secondaryId })?.name ?? ""
        Text("│").foregroundStyle(.tertiary)
        Text(secName)
            .font(.caption)
            .foregroundStyle(.secondary)
        unsplitButton
        if availableSessions.count >= 2 {
            gridExpandMenu(fixedId1: session.id, fixedId2: secondaryId, isVerticalBase: isVertical)
        }
    }

    private var unsplitButton: some View {
        Button {
            plugin.unsplit()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("取消分屏")
    }

    // 扩展为四宫格：两步选择
    // isVerticalBase=false 时：fixed1=topLeft, fixed2=topRight，选 bottomLeft 和 bottomRight
    // isVerticalBase=true  时：fixed1=topLeft, fixed2=bottomLeft，选 topRight 和 bottomRight
    private func gridExpandMenu(fixedId1: UUID, fixedId2: UUID, isVerticalBase: Bool) -> some View {
        let pending = plugin.pendingGridSlot1
        let pendingName = pending.flatMap { id in allSessions.first(where: { $0.id == id })?.name } ?? ""
        let remaining = availableSessions.filter { $0.id != pending }

        return Menu {
            if let slot1 = pending {
                Section("已选: \(pendingName)") {
                    Button("取消选择") { plugin.pendingGridSlot1 = nil }
                }
                Section("选择第四个终端") {
                    ForEach(remaining, id: \.id) { s in
                        Button(s.name) {
                            if isVerticalBase {
                                // V-split → grid: top=fixed1, bottom=fixed2
                                plugin.splitGrid(topLeft: fixedId1, topRight: slot1,
                                                 bottomLeft: fixedId2, bottomRight: s.id)
                            } else {
                                // H-split → grid: left=fixed1, right=fixed2
                                plugin.splitGrid(topLeft: fixedId1, topRight: fixedId2,
                                                 bottomLeft: slot1, bottomRight: s.id)
                            }
                        }
                    }
                }
            } else {
                Section("选择第三个终端") {
                    ForEach(availableSessions, id: \.id) { s in
                        Button(s.name) {
                            plugin.pendingGridSlot1 = s.id
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.split.2x2")
                .font(.caption)
                .foregroundStyle(pending != nil ? Color.accentColor : .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(pending != nil ? "选择第四个终端完成四宫格" : "扩展为四宫格分屏")
    }
}
