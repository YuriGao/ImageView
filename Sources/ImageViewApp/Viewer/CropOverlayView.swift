import AppKit

final class CropOverlayView: NSView {
    var cropRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: cropRect).stroke()
    }
}
