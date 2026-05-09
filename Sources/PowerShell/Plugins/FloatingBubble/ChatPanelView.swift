import AppKit

@MainActor
protocol ChatPanelViewDelegate: AnyObject {
    func chatPanelDidSubmit(text: String)
}

@MainActor
final class ChatPanelView: NSView {
    weak var delegate: ChatPanelViewDelegate?

    private let titleLabel = NSTextField(labelWithString: "PowerShell AI")
    private let scrollView = NSScrollView()
    private let messageContainer = NSView()
    private let inputField = NSTextField()
    private let sendButton = NSButton(title: "发送", target: nil, action: nil)

    private var messages: [ChatMessage] = []
    private var messageViews: [NSView] = []
    private var messageIsUser: [Bool] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        messageIsUser.append(message.isUser)
        let bubble = createBubbleView(for: message)
        messageViews.append(bubble)
        messageContainer.addSubview(bubble)
        layoutMessages()
        scrollToBottom()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 20/255, green: 20/255, blue: 20/255, alpha: 0.95).cgColor
        layer?.cornerRadius = 12
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        addSubview(titleLabel)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = messageContainer
        messageContainer.wantsLayer = true
        addSubview(scrollView)

        inputField.placeholderString = "输入消息..."
        inputField.font = .systemFont(ofSize: 13)
        inputField.isBordered = true
        inputField.bezelStyle = .roundedBezel
        inputField.focusRingType = .none
        inputField.target = self
        inputField.action = #selector(inputDidSubmit)
        addSubview(inputField)

        sendButton.bezelStyle = .inline
        sendButton.font = .systemFont(ofSize: 12, weight: .medium)
        sendButton.contentTintColor = .systemBlue
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        addSubview(sendButton)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 12
        let titleHeight: CGFloat = 36
        let inputHeight: CGFloat = 44
        let sendWidth: CGFloat = 44

        titleLabel.frame = NSRect(x: inset, y: bounds.height - titleHeight + 8, width: bounds.width - inset * 2, height: 20)

        let scrollY = inputHeight
        let scrollHeight = bounds.height - titleHeight - inputHeight
        scrollView.frame = NSRect(x: 0, y: scrollY, width: bounds.width, height: scrollHeight)

        inputField.frame = NSRect(x: inset, y: 10, width: bounds.width - inset * 2 - sendWidth - 4, height: 24)
        sendButton.frame = NSRect(x: bounds.width - inset - sendWidth, y: 8, width: sendWidth, height: 28)

        layoutMessages()
    }

    private func layoutMessages() {
        let maxWidth = bounds.width * 0.8
        let padding: CGFloat = 12
        var yOffset: CGFloat = 8

        for (index, view) in messageViews.enumerated() {
            let fittingSize = view.fittingSize
            let width = min(fittingSize.width + 24, maxWidth)
            let height = fittingSize.height + 16

            let isUser = messageIsUser[index]
            let x: CGFloat = isUser ? bounds.width - width - padding : padding

            view.frame = NSRect(x: x, y: yOffset, width: width, height: height)
            yOffset += height + 8
        }

        messageContainer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(yOffset, scrollView.bounds.height))
    }

    private func scrollToBottom() {
        let maxScroll = max(0, messageContainer.frame.height - scrollView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxScroll))
    }

    private func createBubbleView(for message: ChatMessage) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 10

        if message.isUser {
            container.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
        } else {
            container.layer?.backgroundColor = NSColor(calibratedRed: 60/255, green: 60/255, blue: 60/255, alpha: 0.9).cgColor
        }

        let label = NSTextField(wrappingLabelWithString: message.content)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        label.isEditable = false
        label.isSelectable = true
        label.drawsBackground = false
        label.isBordered = false
        label.preferredMaxLayoutWidth = bounds.width * 0.8 - 24
        container.addSubview(label)

        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        return container
    }

    @objc private func inputDidSubmit() {
        submitInput()
    }

    @objc private func sendTapped() {
        submitInput()
    }

    private func submitInput() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""
        delegate?.chatPanelDidSubmit(text: text)
    }
}
