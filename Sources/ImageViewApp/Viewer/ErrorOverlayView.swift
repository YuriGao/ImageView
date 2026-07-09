import AppKit

final class ErrorOverlayView: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        drawsBackground = false
        textColor = .secondaryLabelColor
        alignment = .center
        font = .systemFont(ofSize: 15, weight: .medium)
        stringValue = ""
    }

    required init?(coder: NSCoder) {
        nil
    }
}
