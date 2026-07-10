import AppKit

@MainActor
final class FilmstripOverlayView: NSView {
    static var backgroundColor: NSColor { .windowBackgroundColor }
    static var borderColor: NSColor { .separatorColor }
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool { true }

    static func borderWidth(forBackingScaleFactor scaleFactor: CGFloat) -> CGFloat {
        1 / max(1, scaleFactor)
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let options: NSTrackingArea.Options = [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
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

    override func updateLayer() {
        layer?.backgroundColor = Self.backgroundColor.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = Self.borderWidth(forBackingScaleFactor: window?.backingScaleFactor ?? layer?.contentsScale ?? 1)
        layer?.borderColor = Self.borderColor.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
        layer?.shadowOpacity = 0.55
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
