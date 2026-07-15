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
    private let leadingSpacer = NSView()
    private let trailingSpacer = NSView()
    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private let decoder = ImageDecodeService()
    private var leadingSpacerWidthConstraint: NSLayoutConstraint!
    private var trailingSpacerWidthConstraint: NSLayoutConstraint!
    private weak var selectedButton: FilmstripButton?
    private var lastViewportWidth: CGFloat = -1
    private var isUpdatingCenteredLayout = false

    var onSelect: ((ImageItem) -> Void)?

    init() {
        super.init(frame: .zero)
        thumbnailCache.totalCostLimit = ImageCache.defaultThumbnailCostLimit
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        leadingSpacerWidthConstraint = leadingSpacer.widthAnchor.constraint(equalToConstant: 0)
        trailingSpacerWidthConstraint = trailingSpacer.widthAnchor.constraint(equalToConstant: 0)
        leadingSpacerWidthConstraint.isActive = true
        trailingSpacerWidthConstraint.isActive = true
        stack.addArrangedSubview(leadingSpacer)
        stack.addArrangedSubview(trailingSpacer)
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
        selectedButton = nil
        stack.addArrangedSubview(leadingSpacer)

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
            if item == current {
                selectedButton = button
            }
            loadThumbnail(for: item, into: button)
        }

        stack.addArrangedSubview(trailingSpacer)
        updateCenteredLayout(force: true)
    }

    override func layout() {
        super.layout()
        updateCenteredLayout()
    }

    #if DEBUG
    func debugButtons() -> [NSButton] {
        stack.arrangedSubviews.compactMap { $0 as? NSButton }
    }

    func performDebugSelection(_ button: NSButton) {
        selectItem(button)
    }

    func debugSelectedCenterInViewport() -> CGFloat? {
        selectedButton?.frame.midX
    }

    func debugLeadingSpacerWidth() -> CGFloat { leadingSpacer.frame.width }
    func debugTrailingSpacerWidth() -> CGFloat { trailingSpacer.frame.width }
    #endif

    static func thumbnailSize(isSelected: Bool) -> CGSize {
        isSelected ? selectedThumbnailSize : regularThumbnailSize
    }

    @objc private func selectItem(_ sender: NSButton) {
        guard let button = sender as? FilmstripButton else { return }
        onSelect?(button.item)
    }

    private func updateCenteredLayout(force: Bool = false) {
        guard !isUpdatingCenteredLayout else { return }
        let viewportWidth = contentView.bounds.width
        guard viewportWidth > 0,
              force || abs(viewportWidth - lastViewportWidth) > 0.5 else { return }

        isUpdatingCenteredLayout = true
        defer { isUpdatingCenteredLayout = false }
        lastViewportWidth = viewportWidth

        guard let selectedButton else {
            leadingSpacerWidthConstraint.constant = 0
            trailingSpacerWidthConstraint.constant = 0
            resizeDocumentToFit()
            contentView.scroll(to: .zero)
            reflectScrolledClipView(contentView)
            return
        }

        leadingSpacerWidthConstraint.constant = 0
        trailingSpacerWidthConstraint.constant = 0
        resizeDocumentToFit()
        let spacerWidth = max(0, (viewportWidth - selectedButton.frame.width) / 2 - stack.spacing)
        leadingSpacerWidthConstraint.constant = spacerWidth
        trailingSpacerWidthConstraint.constant = spacerWidth
        resizeDocumentToFit()
        centerSelectedThumbnail()
    }

    private func resizeDocumentToFit() {
        stack.layoutSubtreeIfNeeded()
        stack.frame.size = stack.fittingSize
        stack.needsLayout = true
        stack.layoutSubtreeIfNeeded()
    }

    private func centerSelectedThumbnail() {
        guard let selectedButton else { return }
        let selectedCenter = selectedButton.frame.midX
        let maximumOrigin = max(0, stack.frame.width - contentView.bounds.width)
        let originX = min(max(0, selectedCenter - contentView.bounds.width / 2), maximumOrigin)
        contentView.scroll(to: NSPoint(x: originX, y: 0))
        reflectScrolledClipView(contentView)
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
            self.thumbnailCache.setObject(thumbnail, forKey: key, cost: decoded.decodedByteCost)
            button.image = thumbnail
        }
    }
}
