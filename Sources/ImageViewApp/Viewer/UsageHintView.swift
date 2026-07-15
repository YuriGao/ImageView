import AppKit

final class UsageHintView: NSVisualEffectView {
    var onDismiss: (() -> Void)?
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let dismissButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        messageLabel.stringValue = AppStrings.text("usageHint.message")
        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.maximumNumberOfLines = 3
        dismissButton.title = AppStrings.text("usageHint.dismiss")
        dismissButton.bezelStyle = .inline
        dismissButton.target = self
        dismissButton.action = #selector(dismiss(_:))
        dismissButton.setAccessibilityLabel(dismissButton.title)
        let stack = NSStackView(views: [messageLabel, dismissButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 430)
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel(AppStrings.text("usageHint.accessibilityLabel"))
    }

    @objc private func dismiss(_ sender: Any?) { onDismiss?() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
