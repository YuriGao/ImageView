import AppKit

final class HUDTrackingView: NSView {
    var onMouseMoved: (() -> Void)?
    var onFileDropped: ((URL) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        firstFileURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstFileURL(from: sender.draggingPasteboard) else { return false }
        onFileDropped?(url)
        return true
    }

    private func firstFileURL(from pasteboard: NSPasteboard) -> URL? {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL
    }

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
