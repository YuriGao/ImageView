import AppKit
import ImageViewCore

@MainActor
final class FilmstripView: NSScrollView {
    static let regularThumbnailSize = CGSize(width: 72, height: 64)
    static let selectedThumbnailSize = CGSize(width: 86, height: 76)
    static let thumbnailDecodeMaxPixelSize: CGFloat = 192
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
    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private let decoder = ImageDecodeService()

    var onSelect: ((ImageItem) -> Void)?

    init() {
        super.init(frame: .zero)
        hasHorizontalScroller = false
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
            let thumbnailSize = Self.thumbnailSize(isSelected: item == current)
            button.bezelStyle = .regularSquare
            button.isBordered = item == current
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.toolTip = item.url.lastPathComponent
            button.setButtonType(.momentaryPushIn)
            button.target = self
            button.action = #selector(selectItem(_:))
            button.widthAnchor.constraint(equalToConstant: thumbnailSize.width).isActive = true
            button.heightAnchor.constraint(equalToConstant: thumbnailSize.height).isActive = true
            stack.addArrangedSubview(button)
            loadThumbnail(for: item, into: button)
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

    static func thumbnailSize(isSelected: Bool) -> CGSize {
        isSelected ? selectedThumbnailSize : regularThumbnailSize
    }

    @objc private func selectItem(_ sender: NSButton) {
        guard let button = sender as? FilmstripButton else { return }
        onSelect?(button.item)
    }

    private func loadThumbnail(for item: ImageItem, into button: FilmstripButton) {
        let key = item.url as NSURL
        if let thumbnail = thumbnailCache.object(forKey: key) {
            button.image = thumbnail
            return
        }

        let decoder = decoder
        let maxPixelSize = Self.thumbnailDecodeMaxPixelSize
        Task { @MainActor [weak self, weak button] in
            guard let decoded = await Task.detached(priority: .utility, operation: {
                try? decoder.decode(
                    url: item.url,
                    format: item.format,
                    maxPixelSize: maxPixelSize
                )
            }).value,
            let self,
            let button,
            button.item.url == item.url else { return }
            let thumbnail = NSImage(cgImage: decoded.cgImage, size: .zero)
            self.thumbnailCache.setObject(thumbnail, forKey: key)
            button.image = thumbnail
        }
    }
}
