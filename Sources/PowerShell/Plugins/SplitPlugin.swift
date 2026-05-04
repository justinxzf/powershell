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

    func setup() {
        PluginManager.shared.registerSplitPlugin(self)
    }

    // MARK: - Split Operations

    func splitHorizontal(left: UUID, right: UUID) {
        storedSplitLayout = nil
        splitLayout = .horizontal(left: left, right: right)
        splitHRatio = 0.5
    }

    func splitVertical(top: UUID, bottom: UUID) {
        storedSplitLayout = nil
        splitLayout = .vertical(top: top, bottom: bottom)
        splitVRatio = 0.5
    }

    func splitTopDouble(topLeft: UUID, topRight: UUID, bottom: UUID) {
        storedSplitLayout = nil
        splitLayout = .topDouble(topLeft: topLeft, topRight: topRight, bottom: bottom)
        splitHRatio = 0.5
        splitVRatio = 0.5
    }

    func splitBottomDouble(top: UUID, bottomLeft: UUID, bottomRight: UUID) {
        storedSplitLayout = nil
        splitLayout = .bottomDouble(top: top, bottomLeft: bottomLeft, bottomRight: bottomRight)
        splitHRatio = 0.5
        splitVRatio = 0.5
    }

    func splitGrid(topLeft: UUID, topRight: UUID, bottomLeft: UUID, bottomRight: UUID) {
        storedSplitLayout = nil
        splitLayout = .grid(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
        splitHRatio = 0.5
        splitVRatio = 0.5
    }

    func unsplit() {
        storedSplitLayout = nil
        splitLayout = nil
    }

    // MARK: - Layout Helpers

    func isPrimary(sessionId: UUID) -> Bool {
        switch splitLayout {
        case .horizontal(let l, _): return l == sessionId
        case .vertical(let t, _): return t == sessionId
        case .topDouble(let tl, _, _): return tl == sessionId
        case .bottomDouble(let t, _, _): return t == sessionId
        case .grid(let tl, _, _, _): return tl == sessionId
        default: return false
        }
    }

    func paneFrame(for sessionId: UUID, W: CGFloat, H: CGFloat) -> CGRect? {
        let hr = splitHRatio
        let vr = splitVRatio
        switch splitLayout {
        case .horizontal(let l, let r):
            if sessionId == l { return CGRect(x: 0,      y: 0,      width: W * hr,       height: H) }
            if sessionId == r { return CGRect(x: W * hr,  y: 0,      width: W * (1 - hr), height: H) }
        case .vertical(let t, let b):
            if sessionId == t { return CGRect(x: 0, y: 0,      width: W, height: H * vr) }
            if sessionId == b { return CGRect(x: 0, y: H * vr, width: W, height: H * (1 - vr)) }
        case .topDouble(let tl, let tr, let b):
            if sessionId == tl { return CGRect(x: 0,      y: 0,      width: W * hr,       height: H * vr) }
            if sessionId == tr { return CGRect(x: W * hr,  y: 0,      width: W * (1 - hr), height: H * vr) }
            if sessionId == b  { return CGRect(x: 0,      y: H * vr, width: W,             height: H * (1 - vr)) }
        case .bottomDouble(let t, let bl, let br):
            if sessionId == t  { return CGRect(x: 0,      y: 0,      width: W,             height: H * vr) }
            if sessionId == bl { return CGRect(x: 0,      y: H * vr, width: W * hr,        height: H * (1 - vr)) }
            if sessionId == br { return CGRect(x: W * hr,  y: H * vr, width: W * (1 - hr), height: H * (1 - vr)) }
        case .grid(let tl, let tr, let bl, let br):
            if sessionId == tl { return CGRect(x: 0,      y: 0,      width: W * hr,       height: H * vr) }
            if sessionId == tr { return CGRect(x: W * hr,  y: 0,      width: W * (1 - hr), height: H * vr) }
            if sessionId == bl { return CGRect(x: 0,      y: H * vr, width: W * hr,       height: H * (1 - vr)) }
            if sessionId == br { return CGRect(x: W * hr,  y: H * vr, width: W * (1 - hr), height: H * (1 - vr)) }
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
        case .topDouble(let tl, _, _):
            if sessionId == tl { return .gridControl }
            if splitLayout!.contains(sessionId) { return .secondary }
        case .bottomDouble(let t, _, _):
            if sessionId == t { return .gridControl }
            if splitLayout!.contains(sessionId) { return .secondary }
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
        case .bottomDouble:
            SplitDividerView(axis: .horizontal, ratio: $plugin.splitVRatio, totalSize: size.height)
            SplitDividerView(axis: .vertical, ratio: $plugin.splitHRatio, totalSize: size.width)
                .frame(height: size.height * (1 - plugin.splitVRatio))
                .frame(maxHeight: .infinity, alignment: .bottom)
        case .topDouble:
            SplitDividerView(axis: .horizontal, ratio: $plugin.splitVRatio, totalSize: size.height)
            SplitDividerView(axis: .vertical, ratio: $plugin.splitHRatio, totalSize: size.width)
                .frame(height: size.height * plugin.splitVRatio)
                .frame(maxHeight: .infinity, alignment: .top)
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
            case .topDouble(let tl, let tr, let b): ids.formUnion([tl, tr, b])
            case .bottomDouble(let t, let bl, let br): ids.formUnion([t, bl, br])
            case .grid(let tl, let tr, let bl, let br): ids.formUnion([tl, tr, bl, br])
            case .none: break
            }
            return ids
        }()
        return allSessions.filter { !excluded.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: 8) {
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
        .fixedSize()
    }

    // MARK: - Single pane buttons

    @ViewBuilder
    private var splitMenuView: some View {
        splitDirectionButton(layout: .horizontalSplit)
        splitDirectionButton(layout: .verticalSplit)
        splitTripleButton(topDouble: true)
        splitTripleButton(topDouble: false)
        splitGridButton
    }

    private enum SplitDirection {
        case horizontalSplit, verticalSplit
        var icon: String {
            switch self {
            case .horizontalSplit: return "rectangle.split.2x1"
            case .verticalSplit: return "rectangle.split.1x2"
            }
        }
        var help: String {
            switch self {
            case .horizontalSplit: return "左右分屏"
            case .verticalSplit: return "上下分屏"
            }
        }
    }

    @ViewBuilder
    private func splitDirectionButton(layout: SplitDirection) -> some View {
        let others = allSessions.filter { $0.id != session.id }
        if !others.isEmpty {
            Menu {
                ForEach(others, id: \.id) { s in
                    Button(s.name) {
                        let sid = session.id, oid = s.id
                        Task { @MainActor in
                            switch layout {
                            case .horizontalSplit: plugin.splitHorizontal(left: sid, right: oid)
                            case .verticalSplit:   plugin.splitVertical(top: sid, bottom: oid)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: layout.icon).font(.caption).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(layout.help)
        }
    }

    // 上2下1 / 上1下2：直接展示所有终端对，单次点击完成
    @ViewBuilder
    private func splitTripleButton(topDouble: Bool) -> some View {
        let others = allSessions.filter { $0.id != session.id }
        let pairs = makePairs(others)
        if !pairs.isEmpty {
            let icon = topDouble ? "rectangle.topthird.inset.filled" : "rectangle.bottomthird.inset.filled"
            let help = topDouble ? "上2下1分屏" : "上1下2分屏"
            Menu {
                ForEach(pairs.indices, id: \.self) { i in
                    let (s1, s2) = pairs[i]
                    Button("\(s1.name)  ·  \(s2.name)") {
                        let sid = session.id, id1 = s1.id, id2 = s2.id
                        Task { @MainActor in
                            if topDouble {
                                plugin.splitTopDouble(topLeft: sid, topRight: id1, bottom: id2)
                            } else {
                                plugin.splitBottomDouble(top: sid, bottomLeft: id1, bottomRight: id2)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(help)
        }
    }

    // 四宫格：直接展示所有三终端组合，单次点击完成
    @ViewBuilder
    private var splitGridButton: some View {
        let others = allSessions.filter { $0.id != session.id }
        let triples = makeTriples(others)
        if !triples.isEmpty {
            Menu {
                ForEach(triples.indices, id: \.self) { i in
                    let (s1, s2, s3) = triples[i]
                    Button("\(s1.name)  ·  \(s2.name)  ·  \(s3.name)") {
                        let sid = session.id, id1 = s1.id, id2 = s2.id, id3 = s3.id
                        Task { @MainActor in
                            plugin.splitGrid(topLeft: sid, topRight: id1, bottomLeft: id2, bottomRight: id3)
                        }
                    }
                }
            } label: {
                Image(systemName: "rectangle.split.2x2").font(.caption).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("四宫格分屏")
        }
    }

    // MARK: - Two-pane summary & expand

    @ViewBuilder
    private func splitSummaryView(secondaryId: UUID, isVertical: Bool) -> some View {
        let secName = allSessions.first(where: { $0.id == secondaryId })?.name ?? ""
        Text("│").foregroundStyle(.tertiary)
        Text(secName).font(.caption).foregroundStyle(.secondary)
        unsplitButton
        if !availableSessions.isEmpty {
            expandMenu(fixedId1: session.id, fixedId2: secondaryId, isVerticalBase: isVertical)
        }
    }

    private var unsplitButton: some View {
        Button {
            plugin.unsplit()
        } label: {
            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("取消分屏")
    }

    // 从2格扩展：三宫格选1个，四宫格选一对
    private func expandMenu(fixedId1: UUID, fixedId2: UUID, isVerticalBase: Bool) -> some View {
        let avail = availableSessions
        let pairs = makePairs(avail)

        return Menu {
            Section("扩展为上2下1") {
                ForEach(avail, id: \.id) { s in
                    Button(s.name) {
                        let id = s.id
                        Task { @MainActor in
                            if isVerticalBase {
                                plugin.splitTopDouble(topLeft: fixedId1, topRight: id, bottom: fixedId2)
                            } else {
                                plugin.splitTopDouble(topLeft: fixedId1, topRight: fixedId2, bottom: id)
                            }
                        }
                    }
                }
            }
            Section("扩展为上1下2") {
                ForEach(avail, id: \.id) { s in
                    Button(s.name) {
                        let id = s.id
                        Task { @MainActor in
                            if isVerticalBase {
                                plugin.splitBottomDouble(top: fixedId1, bottomLeft: fixedId2, bottomRight: id)
                            } else {
                                plugin.splitBottomDouble(top: fixedId1, bottomLeft: fixedId2, bottomRight: id)
                            }
                        }
                    }
                }
            }
            if !pairs.isEmpty {
                Section("扩展为四宫格") {
                    ForEach(pairs.indices, id: \.self) { i in
                        let (s1, s2) = pairs[i]
                        Button("\(s1.name)  ·  \(s2.name)") {
                            let id1 = s1.id, id2 = s2.id
                            Task { @MainActor in
                                if isVerticalBase {
                                    plugin.splitGrid(topLeft: fixedId1, topRight: id1,
                                                     bottomLeft: fixedId2, bottomRight: id2)
                                } else {
                                    plugin.splitGrid(topLeft: fixedId1, topRight: fixedId2,
                                                     bottomLeft: id1, bottomRight: id2)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.split.2x2").font(.caption).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("扩展分屏布局")
    }

    // MARK: - Combination helpers

    private func makePairs(_ sessions: [Session]) -> [(Session, Session)] {
        var result: [(Session, Session)] = []
        for i in sessions.indices {
            for j in (i + 1)..<sessions.count {
                result.append((sessions[i], sessions[j]))
            }
        }
        return result
    }

    private func makeTriples(_ sessions: [Session]) -> [(Session, Session, Session)] {
        var result: [(Session, Session, Session)] = []
        for i in sessions.indices {
            for j in (i + 1)..<sessions.count {
                for k in (j + 1)..<sessions.count {
                    result.append((sessions[i], sessions[j], sessions[k]))
                }
            }
        }
        return result
    }
}
