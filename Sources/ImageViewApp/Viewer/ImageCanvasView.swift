import AppKit
import ImageViewCore

final class ImageCanvasView: NSView {
    var image: DecodedImage? {
        didSet { needsDisplay = true }
    }

    var scale: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    var offset: CGPoint = .zero {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
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
