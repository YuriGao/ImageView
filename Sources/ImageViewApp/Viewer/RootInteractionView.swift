import AppKit

final class RootInteractionView: NSView {
    var onFileDropped: ((URL) -> Void)?
    var onPointerMoved: (() -> Void)?
    private var pointerTrackingArea: NSTrackingArea?
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

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let options: NSTrackingArea.Options = [.activeInKeyWindow, .inVisibleRect, .mouseMoved]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?()
        super.mouseMoved(with: event)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
