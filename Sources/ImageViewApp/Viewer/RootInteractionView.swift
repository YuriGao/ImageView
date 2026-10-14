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
        // 窗口开启了 acceptsMouseMovedEvents，整块屏幕上的鼠标移动都会经响应链送达这里，
        // 与跟踪区域无关；只有落在窗口范围内的移动才应算作"指针在窗口里"，
        // 否则鼠标在窗口外移动也会唤出翻页箭头和胶片条。
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            super.mouseMoved(with: event)
            return
        }
        onPointerMoved?()
        super.mouseMoved(with: event)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
