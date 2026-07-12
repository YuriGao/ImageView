import AppKit

@MainActor
final class HoverToolbarButton: NSButton {
    static let controlSize = NSSize(width: 24, height: 24)

    private var isHovered = false
    private var isPressed = false
    private var focusedForTesting: Bool?
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: NSSize { Self.controlSize }

    override var acceptsFirstResponder: Bool { true }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isHovered = false
                isPressed = false
            }
            updateAppearance()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = isEnabled
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag && isEnabled
        updateAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        needsDisplay = true
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        needsDisplay = true
        return resignedFirstResponder
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        guard testingShowsFocus else { return }
        NSFocusRingPlacement.only.set()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
    }

    var testingShowsHover: Bool { isEnabled && isHovered && !isPressed }
    var testingShowsPressed: Bool { isEnabled && isPressed }
    var testingShowsFocus: Bool {
        focusedForTesting ?? (window?.firstResponder === self)
    }

    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered && isEnabled
        updateAppearance()
    }

    func setFocusedForTesting(_ focused: Bool) {
        focusedForTesting = focused
        needsDisplay = true
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.controlSize.width),
            heightAnchor.constraint(equalToConstant: Self.controlSize.height)
        ])
        bezelStyle = .toolbar
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 6
        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundColor: NSColor?
        if testingShowsPressed {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.20)
        } else if testingShowsHover {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
        } else {
            backgroundColor = nil
        }
        layer?.backgroundColor = backgroundColor?.cgColor
        contentTintColor = isEnabled ? .labelColor : .secondaryLabelColor
        needsDisplay = true
    }
}
