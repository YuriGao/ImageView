import AppKit

final class ErrorStateView: NSView {
    var onRetryRequested: (() -> Void)?

    private let messageLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton()

    var message: String {
        get { messageLabel.stringValue }
        set { messageLabel.stringValue = newValue }
    }

    init(preferredLanguages: [String] = Locale.preferredLanguages) {
        super.init(frame: .zero)

        messageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byWordWrapping

        retryButton.title = AppStrings.text("errorState.retry", preferredLanguages: preferredLanguages)
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(requestRetry(_:))
        retryButton.setAccessibilityLabel(retryButton.title)

        let stack = NSStackView(views: [messageLabel, retryButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    @objc private func requestRetry(_ sender: Any?) {
        onRetryRequested?()
    }

    var messageForTesting: String { messageLabel.stringValue }
    var buttonTitleForTesting: String { retryButton.title }
    var retryButtonForTesting: NSButton { retryButton }

    func performRetryForTesting() {
        requestRetry(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
