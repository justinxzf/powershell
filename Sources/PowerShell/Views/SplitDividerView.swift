import SwiftUI
import AppKit

enum DividerAxis {
    case vertical   // 竖向分割线，用于左右分屏
    case horizontal // 横向分割线，用于上下分屏
}

struct SplitDividerView: View {
    let axis: DividerAxis
    @Binding var ratio: Double
    let totalSize: CGFloat

    /// 命中区域厚度（比可见线宽，方便拖拽）
    private let hitThickness: CGFloat = 12

    @State private var isDragging = false
    @State private var dragStartRatio: Double = 0.5

    var body: some View {
        DividerHandle(
            axis: axis,
            isActive: isDragging,
            onDragStart: {
                dragStartRatio = ratio
                isDragging = true
            },
            onDragChange: { delta in
                // AppKit 的 y 轴向上为正，横向分割线拖拽方向需取反：向下拖动应让上方窗口变大
                let axisDelta = axis == .vertical ? delta : -delta
                ratio = max(0.2, min(0.8, dragStartRatio + Double(axisDelta) / Double(totalSize)))
            },
            onDragEnd: {
                isDragging = false
            }
        )
        .frame(
            width:  axis == .vertical   ? hitThickness : nil,
            height: axis == .horizontal ? hitThickness : nil
        )
        .frame(
            maxWidth:  axis == .horizontal ? .infinity : nil,
            maxHeight: axis == .vertical   ? .infinity : nil
        )
        .offset(
            x: axis == .vertical   ? totalSize * ratio - hitThickness / 2 : 0,
            y: axis == .horizontal ? totalSize * ratio - hitThickness / 2 : 0
        )
    }
}

// MARK: - AppKit-backed drag handle

/// 分隔栏必须用 AppKit NSView 承载：终端面板是 LocalProcessTerminalView（NSView），
/// 会直接吞掉鼠标事件用于文本选择。纯 SwiftUI 的 Rectangle + DragGesture 位于兄弟
/// NSView 之下，命中测试会被终端视图抢走，导致无法拖拽。用 NSView 承载后（ZStack 中
/// 位于终端之后 → AppKit 子视图顺序更靠上）即可稳定接收拖拽。
private struct DividerHandle: NSViewRepresentable {
    let axis: DividerAxis
    let isActive: Bool
    let onDragStart: () -> Void
    let onDragChange: (CGFloat) -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> DividerHandleNSView {
        let view = DividerHandleNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: DividerHandleNSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: DividerHandleNSView) {
        view.axis = axis
        view.onDragStart = onDragStart
        view.onDragChange = onDragChange
        view.onDragEnd = onDragEnd
        if view.isActive != isActive {
            view.isActive = isActive
            view.needsDisplay = true
        }
        view.window?.invalidateCursorRects(for: view)
    }
}

final class DividerHandleNSView: NSView {
    var axis: DividerAxis = .vertical
    var isActive = false
    var onDragStart: (() -> Void)?
    var onDragChange: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    private var startLocation: NSPoint = .zero

    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .vertical ? .resizeLeftRight : .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        let lineThickness: CGFloat = isActive ? 3 : 1
        let color = isActive ? NSColor.controlAccentColor : NSColor.separatorColor
        color.setFill()
        let lineRect: NSRect
        if axis == .vertical {
            lineRect = NSRect(x: (bounds.width - lineThickness) / 2, y: 0,
                              width: lineThickness, height: bounds.height)
        } else {
            lineRect = NSRect(x: 0, y: (bounds.height - lineThickness) / 2,
                              width: bounds.width, height: lineThickness)
        }
        lineRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        startLocation = event.locationInWindow
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = event.locationInWindow
        let delta = axis == .vertical
            ? (loc.x - startLocation.x)
            : (loc.y - startLocation.y)
        onDragChange?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}
