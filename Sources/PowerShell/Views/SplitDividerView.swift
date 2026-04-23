import SwiftUI
import AppKit

struct SplitDividerView: View {
    @Binding var ratio: Double
    let totalWidth: CGFloat

    @State private var isDragging = false
    @State private var dragStartRatio: Double = 0.5

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor : Color(nsColor: .separatorColor))
            .frame(width: isDragging ? 3 : 1)
            .frame(maxHeight: .infinity)
            .offset(x: totalWidth * ratio - 1)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartRatio = ratio
                        }
                        let newRatio = dragStartRatio + value.translation.width / totalWidth
                        ratio = max(0.2, min(0.8, newRatio))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }
}
