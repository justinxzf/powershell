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

    @State private var isDragging = false
    @State private var dragStartRatio: Double = 0.5

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor : Color(nsColor: .separatorColor))
            .frame(
                width:  axis == .vertical   ? (isDragging ? 3 : 1) : nil,
                height: axis == .horizontal ? (isDragging ? 3 : 1) : nil
            )
            .frame(
                maxWidth:  axis == .horizontal ? .infinity : nil,
                maxHeight: axis == .vertical   ? .infinity : nil
            )
            .offset(
                x: axis == .vertical   ? totalSize * ratio - 1 : 0,
                y: axis == .horizontal ? totalSize * ratio - 1 : 0
            )
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartRatio = ratio
                        }
                        let delta = axis == .vertical ? value.translation.width : value.translation.height
                        ratio = max(0.2, min(0.8, dragStartRatio + delta / totalSize))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { hovering in
                if hovering {
                    (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
