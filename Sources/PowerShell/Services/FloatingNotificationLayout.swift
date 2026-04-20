import AppKit

struct FloatingNotificationLayout {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let topInset: CGFloat
    let rightInset: CGFloat
    let spacing: CGFloat

    func frames(
        for presentations: [FloatingNotificationCenter.Presentation],
        visibleFrame: NSRect
    ) -> [NSRect] {
        let x = visibleFrame.maxX - rightInset - cardWidth
        var currentTop = visibleFrame.maxY - topInset

        return presentations.map { presentation in
            let height = height(for: presentation)
            let frame = NSRect(x: x, y: currentTop - height, width: cardWidth, height: height)
            currentTop = frame.minY - spacing
            return frame
        }
    }

    private func height(for presentation: FloatingNotificationCenter.Presentation) -> CGFloat {
        switch presentation {
        case .card:
            return cardHeight
        }
    }
}
