import AppKit
import ImageViewCore

@MainActor
final class FilmstripView: NSScrollView {
    private final class FilmstripButton: NSButton {
        let item: ImageItem

        init(item: ImageItem) {
            self.item = item
            super.init(frame: .zero)
            title = item.url.deletingPathExtension().lastPathComponent
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }
    }

    private let stack = NSStackView()

    var onSelect: ((ImageItem) -> Void)?

    init() {
        super.init(frame: .zero)
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        documentView = stack
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(items: [ImageItem], current: ImageItem?) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for item in items {
            let button = FilmstripButton(item: item)
            button.bezelStyle = .texturedRounded
            button.contentTintColor = item == current ? .controlAccentColor : .secondaryLabelColor
            button.setButtonType(.momentaryPushIn)
            button.target = self
            button.action = #selector(selectItem(_:))
            stack.addArrangedSubview(button)
        }

        stack.layoutSubtreeIfNeeded()
        stack.frame.size = stack.fittingSize
    }

    #if DEBUG
    func debugButtons() -> [NSButton] {
        stack.arrangedSubviews.compactMap { $0 as? NSButton }
    }

    func performDebugSelection(_ button: NSButton) {
        selectItem(button)
    }
    #endif

    @objc private func selectItem(_ sender: NSButton) {
        guard let button = sender as? FilmstripButton else { return }
        onSelect?(button.item)
    }
}
