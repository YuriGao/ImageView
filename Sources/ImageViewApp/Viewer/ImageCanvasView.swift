import AppKit
import ImageViewCore

final class ImageCanvasView: NSView {
    static let trackpadNavigationThreshold: CGFloat = 80

    private enum TrackpadScrollAxis {
        case horizontal
        case vertical
    }

    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onTransformChanged: ((CGFloat) -> Void)?
    private var lastDragLocation: CGPoint?
    private var trackpadScrollAxis: TrackpadScrollAxis?
    private var accumulatedTrackpadDeltaX: CGFloat = 0
    private var didNavigateDuringTrackpadScroll = false

    var backgroundColor: NSColor = .black {
        didSet { needsDisplay = true }
    }

    var image: DecodedImage? {
        didSet {
            currentAnimationFrameIndex = 0
            configureAnimation()
            needsDisplay = true
        }
    }

    private var animationTimer: Timer?
    private(set) var currentAnimationFrameIndex = 0
    var isAnimating: Bool { animationTimer != nil }

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

    var imageDrawRect: CGRect? {
        guard let image,
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        let imageSize = CGSize(width: image.cgImage.width, height: image.cgImage.height)
        let fittedScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * fittedScale * scale, height: imageSize.height * fittedScale * scale)
        return CGRect(
            x: (bounds.width - drawSize.width) / 2 + offset.x,
            y: (bounds.height - drawSize.height) / 2 + offset.y,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    func pixelCropRect(for canvasRect: CGRect) -> CGRect? {
        guard let image,
              let drawRect = imageDrawRect else {
            return nil
        }

        let visibleRect = canvasRect.standardized.intersection(drawRect)
        guard visibleRect.width > 0, visibleRect.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(image.cgImage.width) / drawRect.width
        let scaleY = CGFloat(image.cgImage.height) / drawRect.height
        let pixelRect = CGRect(
            x: (visibleRect.minX - drawRect.minX) * scaleX,
            y: (visibleRect.minY - drawRect.minY) * scaleY,
            width: visibleRect.width * scaleX,
            height: visibleRect.height * scaleY
        ).integral
        let sourceBounds = CGRect(x: 0, y: 0, width: image.cgImage.width, height: image.cgImage.height)
        let clippedRect = pixelRect.intersection(sourceBounds)
        return clippedRect.width > 0 && clippedRect.height > 0 ? clippedRect : nil
    }

    func resetViewTransform() {
        scale = 1.0
        offset = .zero
    }

    func zoomToActualSize() {
        guard let image, bounds.width > 0, bounds.height > 0 else { return }
        let fittedScale = min(bounds.width / CGFloat(image.cgImage.width), bounds.height / CGFloat(image.cgImage.height))
        scale = min(max(1 / fittedScale, 0.1), 12)
        offset = .zero
    }

    func zoom(by delta: CGFloat, around point: CGPoint) {
        let previousScale = scale
        scale = min(max(scale * delta, 0.1), 12.0)
        let ratio = scale / previousScale
        offset = clampedOffset(for: CGPoint(
            x: point.x - (point.x - offset.x) * ratio,
            y: point.y - (point.y - offset.y) * ratio
        ))
    }

    func pan(by delta: CGPoint) {
        offset = clampedOffset(for: CGPoint(x: offset.x + delta.x, y: offset.y + delta.y))
    }

    func clampedOffset(for proposedOffset: CGPoint) -> CGPoint {
        guard let image,
              bounds.width > 0,
              bounds.height > 0 else { return proposedOffset }
        let imageSize = CGSize(width: image.cgImage.width, height: image.cgImage.height)
        let fittedScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * fittedScale * scale, height: imageSize.height * fittedScale * scale)
        let horizontalLimit = max(0, (drawSize.width - bounds.width) / 2)
        let verticalLimit = max(0, (drawSize.height - bounds.height) / 2)
        return CGPoint(
            x: min(max(proposedOffset.x, -horizontalLimit), horizontalLimit),
            y: min(max(proposedOffset.y, -verticalLimit), verticalLimit)
        )
    }

    func handleScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        at point: CGPoint,
        modifierFlags: NSEvent.ModifierFlags = [],
        phase: NSEvent.Phase = [],
        momentumPhase: NSEvent.Phase = [],
        hasPreciseScrollingDeltas: Bool = true
    ) {
        if modifierFlags.contains(.option) || modifierFlags.contains(.command) {
            resetTrackpadScrollState()
            guard abs(deltaY) > 0.1 else { return }
            let zoomDelta = max(0.7, min(1.3, 1.0 - (deltaY * 0.01)))
            zoom(by: zoomDelta, around: point)
            return
        }

        if scale > 1.01 {
            resetTrackpadScrollState()
            pan(by: CGPoint(x: -deltaX, y: -deltaY))
            return
        }

        if !momentumPhase.isEmpty {
            resetTrackpadScrollState()
            return
        }

        guard hasPreciseScrollingDeltas else { return }
        if phase.contains(.began) {
            resetTrackpadScrollState()
        }
        defer {
            if phase.contains(.ended) || phase.contains(.cancelled) {
                resetTrackpadScrollState()
            }
        }

        if trackpadScrollAxis == nil, abs(deltaX) > 0.1 || abs(deltaY) > 0.1 {
            trackpadScrollAxis = abs(deltaX) > abs(deltaY) ? .horizontal : .vertical
        }
        guard trackpadScrollAxis == .horizontal else { return }

        accumulatedTrackpadDeltaX += deltaX
        guard !didNavigateDuringTrackpadScroll,
              abs(accumulatedTrackpadDeltaX) >= Self.trackpadNavigationThreshold else {
            return
        }

        didNavigateDuringTrackpadScroll = true
        accumulatedTrackpadDeltaX > 0 ? onPrevious?() : onNext?()
    }

    private func resetTrackpadScrollState() {
        trackpadScrollAxis = nil
        accumulatedTrackpadDeltaX = 0
        didNavigateDuringTrackpadScroll = false
    }

    func beginMouseDrag(at point: CGPoint) {
        lastDragLocation = point
    }

    func continueMouseDrag(to point: CGPoint) {
        guard scale > 1.01,
              let lastDragLocation else {
            self.lastDragLocation = point
            return
        }

        pan(by: CGPoint(x: point.x - lastDragLocation.x, y: point.y - lastDragLocation.y))
        self.lastDragLocation = point
    }

    func endMouseDrag() {
        lastDragLocation = nil
    }

    func toggleFitOrActualSize() {
        if abs(scale - 1.0) < 0.01 {
            scale = 2.0
        } else {
            resetViewTransform()
        }
    }

    override func mouseDown(with event: NSEvent) {
        beginMouseDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        continueMouseDrag(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        endMouseDrag()
    }

    override func scrollWheel(with event: NSEvent) {
        handleScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            at: convert(event.locationInWindow, from: nil),
            modifierFlags: event.modifierFlags,
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        guard let image else { return }

        guard let drawRect = imageDrawRect else { return }

        let displayedImage = image.animationFrames.indices.contains(currentAnimationFrameIndex)
            ? image.animationFrames[currentAnimationFrameIndex].cgImage
            : image.cgImage
        let appKitImage = NSImage(cgImage: displayedImage, size: drawRect.size)
        appKitImage.draw(in: drawRect)
    }

    func advanceAnimationFrame() {
        guard let image, !image.animationFrames.isEmpty else { return }
        currentAnimationFrameIndex = (currentAnimationFrameIndex + 1) % image.animationFrames.count
        needsDisplay = true
        scheduleNextAnimationFrame()
    }

    private func configureAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard image?.animationFrames.isEmpty == false else { return }
        scheduleNextAnimationFrame()
    }

    private func scheduleNextAnimationFrame() {
        animationTimer?.invalidate()
        guard let image,
              image.animationFrames.indices.contains(currentAnimationFrameIndex) else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: image.animationFrames[currentAnimationFrameIndex].duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.advanceAnimationFrame()
            }
        }
    }
}
