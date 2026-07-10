import AppKit

@MainActor
final class PageNavigationOverlayView: NSView {
    static let controlSize = CGSize(width: 44, height: 64)
    static var backgroundColor: NSColor { .windowBackgroundColor }
    static var borderColor: NSColor { .separatorColor }

    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private var pointerTrackingAreas: [NSTrackingArea] = []

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        configure(
            previousButton,
            symbol: "chevron.left",
            description: "Previous Image",
            action: #selector(showPrevious)
        )
        configure(
            nextButton,
            symbol: "chevron.right",
            description: "Next Image",
            action: #selector(showNext)
        )
        addSubview(previousButton)
        addSubview(nextButton)

        NSLayoutConstraint.activate([
            previousButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: Self.controlSize.width),
            previousButton.heightAnchor.constraint(equalToConstant: Self.controlSize.height),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: Self.controlSize.width),
            nextButton.heightAnchor.constraint(equalToConstant: Self.controlSize.height)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    static func borderWidth(forBackingScaleFactor scaleFactor: CGFloat) -> CGFloat {
        1 / max(1, scaleFactor)
    }

    func update(previousEnabled: Bool, nextEnabled: Bool) {
        previousButton.isEnabled = previousEnabled
        nextButton.isEnabled = nextEnabled
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for button in [previousButton, nextButton] where !button.isHidden {
            let localPoint = button.convert(point, from: self)
            if button.bounds.contains(localPoint) {
                return button.hitTest(localPoint)
            }
        }
        return nil
    }

    override func updateTrackingAreas() {
        pointerTrackingAreas.forEach(removeTrackingArea)
        pointerTrackingAreas = [previousButton, nextButton].map { button in
            let rect = convert(button.bounds, from: button)
            let trackingArea = NSTrackingArea(
                rect: rect,
                options: [.activeInKeyWindow, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            return trackingArea
        }
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
        super.mouseExited(with: event)
    }

    override func layout() {
        super.layout()
        updateButtonLayers()
        updateTrackingAreas()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateButtonLayers()
    }

    @objc private func showPrevious() {
        onPrevious?()
    }

    @objc private func showNext() {
        onNext?()
    }

    private func configure(
        _ button: NSButton,
        symbol: String,
        description: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.target = self
        button.action = action
        button.toolTip = description
    }

    private func updateButtonLayers() {
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 1
        for button in [previousButton, nextButton] {
            button.layer?.backgroundColor = Self.backgroundColor.cgColor
            button.layer?.cornerRadius = 8
            button.layer?.borderWidth = Self.borderWidth(forBackingScaleFactor: scale)
            button.layer?.borderColor = Self.borderColor.cgColor
            button.layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
            button.layer?.shadowOpacity = 0.45
            button.layer?.shadowRadius = 5
            button.layer?.shadowOffset = CGSize(width: 0, height: -1)
        }
    }

    #if DEBUG
    var debugPreviousButton: NSButton { previousButton }
    var debugNextButton: NSButton { nextButton }
    func performDebugPrevious() { showPrevious() }
    func performDebugNext() { showNext() }
    #endif
}
