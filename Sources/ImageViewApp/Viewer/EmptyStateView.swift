import AppKit

final class EmptyStateView: NSView {
    var onOpenRequested: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()

    init(preferredLanguages: [String] = Locale.preferredLanguages) {
        super.init(frame: .zero)

        let text: (String) -> String = {
            AppStrings.text($0, preferredLanguages: preferredLanguages)
        }

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        iconView.image = NSImage(
            systemSymbolName: "photo.on.rectangle.angled",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)

        titleLabel.stringValue = text("emptyState.title")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        messageLabel.stringValue = text("emptyState.message")
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping

        openButton.title = text("emptyState.open")
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(requestOpen(_:))
        openButton.setAccessibilityLabel(openButton.title)

        let stack = NSStackView(views: [iconView, titleLabel, messageLabel, openButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

    @objc private func requestOpen(_ sender: Any?) {
        onOpenRequested?()
    }

    var titleTextForTesting: String { titleLabel.stringValue }
    var messageTextForTesting: String { messageLabel.stringValue }
    var buttonTitleForTesting: String { openButton.title }

    func performOpenForTesting() {
        requestOpen(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
