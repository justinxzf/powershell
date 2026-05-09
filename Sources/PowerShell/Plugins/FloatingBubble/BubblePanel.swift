import AppKit

enum BubblePositionCalculator {
    static func defaultPosition(screenVisibleFrame: NSRect, bubbleSize: CGFloat) -> NSPoint {
        NSPoint(
            x: screenVisibleFrame.maxX - 60 - bubbleSize,
            y: screenVisibleFrame.minY + 60
        )
    }

    static func clamp(point: NSPoint, screenVisibleFrame: NSRect, bubbleSize: CGFloat) -> NSPoint {
        let x = min(max(point.x, screenVisibleFrame.minX), screenVisibleFrame.maxX - bubbleSize)
        let y = min(max(point.y, screenVisibleFrame.minY), screenVisibleFrame.maxY - bubbleSize)
        return NSPoint(x: x, y: y)
    }

    static func chatPanelOrigin(
        bubbleFrame: NSRect,
        chatSize: NSSize,
        screenVisibleFrame: NSRect
    ) -> NSPoint {
        let gap: CGFloat = 8
        let leftX = bubbleFrame.minX - gap - chatSize.width
        if leftX >= screenVisibleFrame.minX {
            let y = min(
                max(bubbleFrame.midY - chatSize.height / 2, screenVisibleFrame.minY),
                screenVisibleFrame.maxY - chatSize.height
            )
            return NSPoint(x: leftX, y: y)
        }
        let rightX = bubbleFrame.maxX + gap
        let y = min(
            max(bubbleFrame.midY - chatSize.height / 2, screenVisibleFrame.minY),
            screenVisibleFrame.maxY - chatSize.height
        )
        return NSPoint(x: rightX, y: y)
    }
}

@MainActor
final class BubblePanel: NSPanel {
    static let bubbleSize: CGFloat = 48

    private let bubbleView: BubblePanelView
    private var dragOffset: NSPoint = .zero

    var onBubbleClicked: (() -> Void)?
    var onPositionChanged: ((NSPoint) -> Void)?

    init() {
        let size = Self.bubbleSize
        bubbleView = BubblePanelView(frame: NSRect(x: 0, y: 0, width: size, height: size))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        contentView = bubbleView
        bubbleView.delegate = self
    }

    func restorePosition() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "floatingBubble.position.x") != nil else {
            moveToDefaultPosition()
            return
        }
        let x = defaults.double(forKey: "floatingBubble.position.x")
        let y = defaults.double(forKey: "floatingBubble.position.y")
        let point = clampedPosition(NSPoint(x: x, y: y))
        setFrameOrigin(point)
    }

    func savePosition() {
        let origin = frame.origin
        UserDefaults.standard.set(origin.x, forKey: "floatingBubble.position.x")
        UserDefaults.standard.set(origin.y, forKey: "floatingBubble.position.y")
    }

    private func moveToDefaultPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let pos = BubblePositionCalculator.defaultPosition(
            screenVisibleFrame: screen.visibleFrame,
            bubbleSize: Self.bubbleSize
        )
        setFrameOrigin(pos)
    }

    private func clampedPosition(_ point: NSPoint) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return point }
        return BubblePositionCalculator.clamp(
            point: point,
            screenVisibleFrame: screen.visibleFrame,
            bubbleSize: Self.bubbleSize
        )
    }
}

extension BubblePanel: BubblePanelViewDelegate {
    func bubbleDidClick() {
        onBubbleClicked?()
    }

    func bubbleDidStartDrag() {
        dragOffset = NSPoint(
            x: NSEvent.mouseLocation.x - frame.origin.x,
            y: NSEvent.mouseLocation.y - frame.origin.y
        )
    }

    func bubbleDidDrag(to screenPoint: NSPoint) {
        let newOrigin = NSPoint(
            x: screenPoint.x - dragOffset.x,
            y: screenPoint.y - dragOffset.y
        )
        setFrameOrigin(clampedPosition(newOrigin))
    }

    func bubbleDidEndDrag() {
        savePosition()
        onPositionChanged?(frame.origin)
    }
}
