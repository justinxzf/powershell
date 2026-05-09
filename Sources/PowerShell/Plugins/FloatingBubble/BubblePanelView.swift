import AppKit

@MainActor
protocol BubblePanelViewDelegate: AnyObject {
    func bubbleDidClick()
    func bubbleDidStartDrag()
    func bubbleDidDrag(to screenPoint: NSPoint)
    func bubbleDidEndDrag()
}

@MainActor
final class BubblePanelView: NSView {
    weak var delegate: BubblePanelViewDelegate?

    private let dragThreshold: CGFloat = 3.0
    private var mouseDownLocation: NSPoint = .zero
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = frameRect.width / 2
        layer?.backgroundColor = NSColor(calibratedRed: 30/255, green: 30/255, blue: 30/255, alpha: 0.92).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) else { return }

        let imageSize = image.size
        let origin = NSPoint(
            x: (bounds.width - imageSize.width) / 2,
            y: (bounds.height - imageSize.height) / 2
        )

        let tinted = NSImage(size: imageSize, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.white.withAlphaComponent(0.8).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownLocation.x
        let dy = current.y - mouseDownLocation.y
        let distance = sqrt(dx * dx + dy * dy)

        if !isDragging && distance > dragThreshold {
            isDragging = true
            delegate?.bubbleDidStartDrag()
        }

        if isDragging {
            delegate?.bubbleDidDrag(to: current)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            delegate?.bubbleDidEndDrag()
        } else {
            animateClick()
            delegate?.bubbleDidClick()
        }
        isDragging = false
    }

    private func animateClick() {
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values = [1.0, 0.9, 1.0]
        anim.keyTimes = [0, 0.5, 1.0]
        anim.duration = 0.1
        layer?.add(anim, forKey: "clickBounce")
    }
}
