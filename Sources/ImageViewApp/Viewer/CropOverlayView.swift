import AppKit

enum CropHandle {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case move
}

final class CropOverlayView: NSView {
    private let minimumCropSide: CGFloat = 24
    private let handleSize: CGFloat = 8
    private let handleHitInset: CGFloat = 6
    private var imageRect = CGRect.zero
    private var activeHandle: CropHandle?
    private var lastDragLocation: CGPoint?

    var cropRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    private(set) var isCropping = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func beginCropping(in imageRect: CGRect) {
        guard imageRect.width >= minimumCropSide,
              imageRect.height >= minimumCropSide else {
            endCropping()
            return
        }

        self.imageRect = imageRect
        cropRect = imageRect.insetBy(dx: imageRect.width * 0.1, dy: imageRect.height * 0.1)
        isCropping = true
        isHidden = false
    }

    func endCropping() {
        isCropping = false
        activeHandle = nil
        lastDragLocation = nil
        isHidden = true
    }

    func moveCrop(by delta: CGPoint) {
        guard isCropping else { return }

        let x = min(max(cropRect.minX + delta.x, imageRect.minX), imageRect.maxX - cropRect.width)
        let y = min(max(cropRect.minY + delta.y, imageRect.minY), imageRect.maxY - cropRect.height)
        cropRect.origin = CGPoint(x: x, y: y)
    }

    func resizeCrop(edge: CropHandle, by delta: CGPoint) {
        guard isCropping else { return }

        var next = cropRect
        switch edge {
        case .topLeft:
            next.origin.x = clampedLeading(cropRect.minX + delta.x, trailing: cropRect.maxX, lowerBound: imageRect.minX)
            next.origin.y = clampedLeading(cropRect.minY + delta.y, trailing: cropRect.maxY, lowerBound: imageRect.minY)
            next.size.width = cropRect.maxX - next.minX
            next.size.height = cropRect.maxY - next.minY
        case .top:
            next.origin.y = clampedLeading(cropRect.minY + delta.y, trailing: cropRect.maxY, lowerBound: imageRect.minY)
            next.size.height = cropRect.maxY - next.minY
        case .topRight:
            next.origin.y = clampedLeading(cropRect.minY + delta.y, trailing: cropRect.maxY, lowerBound: imageRect.minY)
            next.size.height = cropRect.maxY - next.minY
            next.size.width = clampedTrailing(cropRect.maxX + delta.x, leading: cropRect.minX, upperBound: imageRect.maxX) - cropRect.minX
        case .right:
            next.size.width = clampedTrailing(cropRect.maxX + delta.x, leading: cropRect.minX, upperBound: imageRect.maxX) - cropRect.minX
        case .bottomRight:
            next.size.width = clampedTrailing(cropRect.maxX + delta.x, leading: cropRect.minX, upperBound: imageRect.maxX) - cropRect.minX
            next.size.height = clampedTrailing(cropRect.maxY + delta.y, leading: cropRect.minY, upperBound: imageRect.maxY) - cropRect.minY
        case .bottom:
            next.size.height = clampedTrailing(cropRect.maxY + delta.y, leading: cropRect.minY, upperBound: imageRect.maxY) - cropRect.minY
        case .bottomLeft:
            next.origin.x = clampedLeading(cropRect.minX + delta.x, trailing: cropRect.maxX, lowerBound: imageRect.minX)
            next.size.width = cropRect.maxX - next.minX
            next.size.height = clampedTrailing(cropRect.maxY + delta.y, leading: cropRect.minY, upperBound: imageRect.maxY) - cropRect.minY
        case .left:
            next.origin.x = clampedLeading(cropRect.minX + delta.x, trailing: cropRect.maxX, lowerBound: imageRect.minX)
            next.size.width = cropRect.maxX - next.minX
        case .move:
            moveCrop(by: delta)
            return
        }
        cropRect = next
    }

    override func mouseDown(with event: NSEvent) {
        guard isCropping else { return }
        let location = convert(event.locationInWindow, from: nil)
        activeHandle = handle(at: location)
        lastDragLocation = activeHandle == nil ? nil : location
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeHandle,
              let lastDragLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        resizeCrop(edge: activeHandle, by: CGPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y))
        self.lastDragLocation = location
    }

    override func mouseUp(with event: NSEvent) {
        activeHandle = nil
        lastDragLocation = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isCropping else { return }

        let mask = NSBezierPath(rect: bounds)
        mask.appendRect(cropRect)
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.55).setFill()
        mask.fill()

        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: cropRect).stroke()
        NSColor.controlAccentColor.setFill()
        for handleRect in handleRects.values {
            NSBezierPath(rect: handleRect).fill()
        }
    }

    private var handleRects: [CropHandle: CGRect] {
        let halfHandle = handleSize / 2
        let centerX = cropRect.midX
        let centerY = cropRect.midY
        return [
            .topLeft: CGRect(x: cropRect.minX - halfHandle, y: cropRect.minY - halfHandle, width: handleSize, height: handleSize),
            .top: CGRect(x: centerX - halfHandle, y: cropRect.minY - halfHandle, width: handleSize, height: handleSize),
            .topRight: CGRect(x: cropRect.maxX - halfHandle, y: cropRect.minY - halfHandle, width: handleSize, height: handleSize),
            .right: CGRect(x: cropRect.maxX - halfHandle, y: centerY - halfHandle, width: handleSize, height: handleSize),
            .bottomRight: CGRect(x: cropRect.maxX - halfHandle, y: cropRect.maxY - halfHandle, width: handleSize, height: handleSize),
            .bottom: CGRect(x: centerX - halfHandle, y: cropRect.maxY - halfHandle, width: handleSize, height: handleSize),
            .bottomLeft: CGRect(x: cropRect.minX - halfHandle, y: cropRect.maxY - halfHandle, width: handleSize, height: handleSize),
            .left: CGRect(x: cropRect.minX - halfHandle, y: centerY - halfHandle, width: handleSize, height: handleSize)
        ]
    }

    private func handle(at location: CGPoint) -> CropHandle? {
        for handle in [CropHandle.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left] {
            if handleRects[handle]!.insetBy(dx: -handleHitInset, dy: -handleHitInset).contains(location) {
                return handle
            }
        }
        return cropRect.contains(location) ? .move : nil
    }

    private func clampedLeading(_ value: CGFloat, trailing: CGFloat, lowerBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), trailing - minimumCropSide)
    }

    private func clampedTrailing(_ value: CGFloat, leading: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(min(value, upperBound), leading + minimumCropSide)
    }
}
