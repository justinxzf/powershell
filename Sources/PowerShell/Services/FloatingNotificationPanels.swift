import AppKit
import Foundation

@MainActor
protocol FloatingNotificationPresenting: AnyObject {
    func show(title: String, body: String, sessionId: String)
}

@MainActor
final class FloatingNotificationPanelPresenter: FloatingNotificationPresenting {
    private let center: FloatingNotificationCenter
    private let panelControllerFactory: () -> FloatingNotificationPanelControlling
    private lazy var panelController = panelControllerFactory()

    init(
        center: FloatingNotificationCenter = FloatingNotificationCenter(),
        panelControllerFactory: @escaping () -> FloatingNotificationPanelControlling = { FloatingNotificationPanelController() }
    ) {
        self.center = center
        self.panelControllerFactory = panelControllerFactory
    }

    func show(title: String, body: String, sessionId: String) {
        _ = center.enqueue(title: title, body: body, sessionId: sessionId)
        render()
    }

    private func handlePanelAction(_ action: FloatingNotificationPanelAction) {
        switch action {
        case .open(let id, let sessionId):
            center.dismiss(id: id)
            NotificationManager.shared.onNotificationClicked?(sessionId)
        case .close(let id):
            center.dismiss(id: id)
        case .advanceOverflow:
            center.advanceOverflow()
        }

        render()
    }

    private func render() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            panelController.dismissAll()
            return
        }

        let presentations = center.presentations()
        guard !presentations.isEmpty else {
            panelController.dismissAll()
            return
        }

        let layout = FloatingNotificationLayout(
            cardWidth: 300,
            cardHeight: 84,
            summaryHeight: 56,
            topInset: 14,
            rightInset: 14,
            spacing: 10
        )

        let frames = layout.frames(for: presentations, visibleFrame: screen.visibleFrame)
        panelController.render(
            presentations: presentations,
            frames: frames,
            onAction: { [weak self] action in
                self?.handlePanelAction(action)
            }
        )
    }
}

@MainActor
private protocol FloatingNotificationPanelControlling: AnyObject {
    func render(
        presentations: [FloatingNotificationCenter.Presentation],
        frames: [NSRect],
        onAction: @escaping (FloatingNotificationPanelAction) -> Void
    )

    func dismissAll()
}

@MainActor
private final class FloatingNotificationPanelController: FloatingNotificationPanelControlling {
    private var panels: [UUID: FloatingNotificationPanel] = [:]
    private var orderedPanelIDs: [UUID] = []

    func render(
        presentations: [FloatingNotificationCenter.Presentation],
        frames: [NSRect],
        onAction: @escaping (FloatingNotificationPanelAction) -> Void
    ) {
        let targetIDs = presentations.enumerated().map { index, _ in panelID(for: index) }
        let targetIDSet = Set(targetIDs)

        for panelID in orderedPanelIDs where !targetIDSet.contains(panelID) {
            panels[panelID]?.close()
            panels[panelID] = nil
        }

        orderedPanelIDs = targetIDs

        for (index, presentation) in presentations.enumerated() {
            let panelID = targetIDs[index]
            let panel = panels[panelID] ?? FloatingNotificationPanel(identifier: panelID)
            panels[panelID] = panel
            panel.configure(presentation: presentation, frame: frames[index], onAction: onAction)
            panel.orderFrontRegardless()
        }
    }

    func dismissAll() {
        panels.values.forEach { $0.close() }
        panels.removeAll()
        orderedPanelIDs.removeAll()
    }

    private func panelID(for index: Int) -> UUID {
        if index < orderedPanelIDs.count {
            return orderedPanelIDs[index]
        }
        return UUID()
    }
}

@MainActor
private final class FloatingNotificationPanel: NSPanel {
    private let identifierValue: UUID
    private let rootView = FloatingNotificationPanelView(frame: .zero)

    init(identifier: UUID) {
        self.identifierValue = identifier
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 84),
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
        contentView = rootView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(
        presentation: FloatingNotificationCenter.Presentation,
        frame: NSRect,
        onAction: @escaping (FloatingNotificationPanelAction) -> Void
    ) {
        setFrame(frame, display: false)
        rootView.frame = NSRect(origin: .zero, size: frame.size)
        rootView.autoresizingMask = [.width, .height]
        rootView.configure(panelID: identifierValue, presentation: presentation, onAction: onAction)
    }
}

private enum FloatingNotificationPanelAction {
    case open(id: UUID, sessionId: String)
    case close(id: UUID)
    case advanceOverflow
}

private final class FloatingNotificationPanelView: NSView {
    private let backgroundView = NSView(frame: .zero)
    private let titleField = NSTextField(labelWithString: "")
    private let bodyField = NSTextField(labelWithString: "")
    private let footerField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let closeButton = NSButton(frame: .zero)

    private var panelID: UUID?
    private var sessionId: String?
    private var isSummaryCard = false
    private var onAction: ((FloatingNotificationPanelAction) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(
        panelID: UUID,
        presentation: FloatingNotificationCenter.Presentation,
        onAction: @escaping (FloatingNotificationPanelAction) -> Void
    ) {
        self.panelID = panelID
        self.onAction = onAction

        switch presentation {
        case .card(let title, let body, let sessionId, let footer):
            isSummaryCard = false
            self.sessionId = sessionId
            titleField.stringValue = title
            bodyField.stringValue = body
            bodyField.isHidden = false
            footerField.stringValue = footer ?? ""
            footerField.isHidden = footer == nil
            summaryField.isHidden = true
            closeButton.isHidden = false
        case .summary(let hiddenCount):
            isSummaryCard = true
            sessionId = nil
            titleField.stringValue = "更多通知"
            bodyField.isHidden = true
            footerField.isHidden = true
            summaryField.stringValue = "还有 \(hiddenCount) 条通知，点击查看"
            summaryField.isHidden = false
            closeButton.isHidden = true
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        let inset: CGFloat = 12
        let closeSize: CGFloat = 16
        closeButton.frame = NSRect(x: bounds.maxX - inset - closeSize, y: bounds.maxY - inset - closeSize, width: closeSize, height: closeSize)

        let textWidth = bounds.width - inset * 2 - (closeButton.isHidden ? 0 : closeSize + 8)
        titleField.frame = NSRect(x: inset, y: bounds.height - 30, width: textWidth, height: 17)

        if isSummaryCard {
            summaryField.frame = NSRect(x: inset, y: 14, width: bounds.width - inset * 2, height: 18)
        } else {
            bodyField.frame = NSRect(x: inset, y: footerField.isHidden ? 14 : 28, width: bounds.width - inset * 2, height: 32)
            footerField.frame = NSRect(x: inset, y: 12, width: bounds.width - inset * 2, height: 14)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let panelID else { return }

        if isSummaryCard {
            onAction?(.advanceOverflow)
            return
        }

        if let sessionId {
            onAction?(.open(id: panelID, sessionId: sessionId))
        }
    }

    @objc private func closeTapped() {
        guard let panelID else { return }
        onAction?(.close(id: panelID))
    }

    private func setupViews() {
        wantsLayer = true

        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor
        backgroundView.layer?.cornerRadius = 12
        backgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        backgroundView.layer?.borderWidth = 1
        addSubview(backgroundView)

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        addSubview(titleField)

        bodyField.font = .systemFont(ofSize: 12)
        bodyField.textColor = .white.withAlphaComponent(0.82)
        bodyField.lineBreakMode = .byTruncatingTail
        bodyField.maximumNumberOfLines = 2
        addSubview(bodyField)

        footerField.font = .systemFont(ofSize: 11, weight: .medium)
        footerField.textColor = .systemBlue.withAlphaComponent(0.95)
        footerField.lineBreakMode = .byTruncatingTail
        footerField.maximumNumberOfLines = 1
        addSubview(footerField)

        summaryField.font = .systemFont(ofSize: 12, weight: .medium)
        summaryField.textColor = .white.withAlphaComponent(0.82)
        summaryField.lineBreakMode = .byTruncatingTail
        summaryField.maximumNumberOfLines = 1
        addSubview(summaryField)

        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .white.withAlphaComponent(0.65)
        closeButton.focusRingType = .none
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)
    }
}
