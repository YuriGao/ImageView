import AppKit
import ImageViewCore

@MainActor
final class FilmstripView: NSScrollView {
    static let regularThumbnailSize = CGSize(width: 72, height: 64)
    static let selectedThumbnailSize = CGSize(width: 86, height: 76)
    static let thumbnailDecodeMaxPixelSize: CGFloat = 192
    static let retainedItemRadius = 20
    static let maximumRetainedItemCount = retainedItemRadius * 2 + 1
    private final class FilmstripButton: NSButton {
        let item: ImageItem
        var thumbnailRequest: ThumbnailRequest?
        private var widthConstraint: NSLayoutConstraint!
        private var heightConstraint: NSLayoutConstraint!

        init(item: ImageItem, isSelected: Bool) {
            self.item = item
            super.init(frame: .zero)
            title = item.url.deletingPathExtension().lastPathComponent
            configure(isSelected: isSelected)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        deinit {
            thumbnailRequest?.cancel()
        }

        func configure(isSelected: Bool) {
            let thumbnailSize = FilmstripView.thumbnailSize(isSelected: isSelected)
            isBordered = isSelected
            if widthConstraint == nil {
                widthConstraint = widthAnchor.constraint(equalToConstant: thumbnailSize.width)
                heightConstraint = heightAnchor.constraint(equalToConstant: thumbnailSize.height)
                widthConstraint.isActive = true
                heightConstraint.isActive = true
            } else {
                widthConstraint.constant = thumbnailSize.width
                heightConstraint.constant = thumbnailSize.height
            }
        }
    }

    private let stack = NSStackView()
    private let leadingSpacer = NSView()
    private let trailingSpacer = NSView()
    private let thumbnailProvider: ThumbnailProvider
    private var leadingSpacerWidthConstraint: NSLayoutConstraint!
    private var trailingSpacerWidthConstraint: NSLayoutConstraint!
    private weak var selectedButton: FilmstripButton?
    private var lastViewportWidth: CGFloat = -1
    private var isUpdatingCenteredLayout = false
    private var allItems: [ImageItem] = []
    private var retainedItems: [ImageItem] = []

    var onSelect: ((ImageItem) -> Void)?

    init(thumbnailProvider: ThumbnailProvider = ThumbnailProvider(maxPixelSize: thumbnailDecodeMaxPixelSize)) {
        self.thumbnailProvider = thumbnailProvider
        super.init(frame: .zero)
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
        let contentChanged = items != allItems
        allItems = items
        guard let current,
              let currentIndex = items.firstIndex(of: current) else {
            if !retainedItems.isEmpty || selectedButton != nil {
                rebuild(items: [], current: nil)
            } else {
                contentView.scroll(to: .zero)
                reflectScrolledClipView(contentView)
            }
            return
        }

        if contentChanged || !retainedItems.contains(current) {
            rebuild(items: Self.retainedWindow(in: items, centeredAt: currentIndex), current: current)
        } else {
            updateSelection(current: current)
            updateCenteredLayout(force: true)
        }
    }

    private func rebuild(items: [ImageItem], current: ImageItem?) {
        stack.arrangedSubviews.forEach {
            ($0 as? FilmstripButton)?.thumbnailRequest?.cancel()
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        retainedItems = items
        selectedButton = nil
        lastViewportWidth = -1
        stack.addArrangedSubview(leadingSpacer)

        for item in items {
            let button = FilmstripButton(item: item, isSelected: item == current)
            button.bezelStyle = .regularSquare
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.toolTip = item.url.lastPathComponent
            button.setButtonType(.momentaryPushIn)
            button.target = self
            button.action = #selector(selectItem(_:))
            stack.addArrangedSubview(button)
            if item == current {
                selectedButton = button
            }
            loadThumbnail(for: item, into: button)
        }

        stack.addArrangedSubview(trailingSpacer)
        updateCenteredLayout(force: true)
    }

    private func updateSelection(current: ImageItem) {
        selectedButton = nil
        for case let button as FilmstripButton in stack.arrangedSubviews {
            let isSelected = button.item == current
            button.configure(isSelected: isSelected)
            if isSelected {
                selectedButton = button
            }
        }
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

    static func retainedWindow(in items: [ImageItem], centeredAt index: Int) -> [ImageItem] {
        guard items.indices.contains(index) else { return [] }
        let lowerBound = max(items.startIndex, index - retainedItemRadius)
        let upperBound = min(items.endIndex, index + retainedItemRadius + 1)
        return Array(items[lowerBound..<upperBound])
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
        button.thumbnailRequest = thumbnailProvider.loadThumbnail(for: item) { [weak button] result in
            Task { @MainActor [weak button] in
                guard let button,
                      button.item.id == item.id,
                      case let .success(thumbnail) = result else { return }
                button.image = thumbnail
            }
        }
    }
}
