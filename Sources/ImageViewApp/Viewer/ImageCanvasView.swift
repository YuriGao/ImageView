import AppKit
import ImageViewCore

final class ImageCanvasView: NSView {
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onTransformChanged: ((CGFloat) -> Void)?

    var backgroundColor: NSColor = .black {
        didSet { needsDisplay = true }
    }

    var image: DecodedImage? {
        didSet { needsDisplay = true }
    }

    var scale: CGFloat = 1.0 {
        didSet {
            needsDisplay = true
            onTransformChanged?(scale)
        }
    }

    var offset: CGPoint = .zero {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func resetViewTransform() {
        scale = 1.0
        offset = .zero
    }

    func zoom(by delta: CGFloat, around point: CGPoint) {
        let previousScale = scale
        scale = min(max(scale * delta, 0.1), 12.0)
        let ratio = scale / previousScale
        offset = CGPoint(
            x: point.x - (point.x - offset.x) * ratio,
            y: point.y - (point.y - offset.y) * ratio
        )
    }

    func pan(by delta: CGPoint) {
        offset = CGPoint(x: offset.x + delta.x, y: offset.y + delta.y)
    }

    func toggleFitOrActualSize() {
        if abs(scale - 1.0) < 0.01 {
            scale = 2.0
        } else {
            resetViewTransform()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        guard let image else { return }

        let imageSize = CGSize(width: image.cgImage.width, height: image.cgImage.height)
        let fittedScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawScale = fittedScale * scale
        let drawSize = CGSize(width: imageSize.width * drawScale, height: imageSize.height * drawScale)
        let origin = CGPoint(
            x: (bounds.width - drawSize.width) / 2 + offset.x,
            y: (bounds.height - drawSize.height) / 2 + offset.y
        )

        NSGraphicsContext.current?.cgContext.interpolationQuality = .high
        NSGraphicsContext.current?.cgContext.draw(image.cgImage, in: CGRect(origin: origin, size: drawSize))
    }
}
