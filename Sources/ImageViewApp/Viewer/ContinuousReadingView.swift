import AppKit
import ImageViewCore

struct ContinuousReadingPage {
    let item: ImageItem
    let image: DecodedImage?
}

final class ContinuousReadingView: NSView {
    static let preloadRadius = 2
    static let maximumDecodedPageCount = preloadRadius * 2 + 1
    static let maximumDecodedByteCost = ImageCache.defaultFullImageCostLimit

    private let scrollView = NSScrollView()
    private let clipView = ContinuousReadingClipView()
    private let document = ContinuousReadingDocumentView()
    private var currentItemID: ImageItem.ID?
    private var focusUpdateTimer: Timer?
    private var isApplyingPages = false

    var onFocusedItemChanged: ((ImageItem.ID) -> Void)?

    var testingPageCount: Int { document.pages.count }
    var testingDecodedPageCount: Int { document.pages.filter { $0.image != nil }.count }
    var testingPageURLs: [URL] { document.pages.map { $0.item.url } }

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.documentView = document
        clipView.onBoundsOriginChanged = { [weak self] in self?.scheduleFocusUpdate() }
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(AppStrings.text("viewer.continuousReading.accessibilityLabel"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = max(scrollView.contentSize.width, 1)
        let height = document.requiredHeight(for: width)
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(height, scrollView.contentSize.height))
    }

    func apply(pages: [ContinuousReadingPage], currentItemID: ImageItem.ID?) {
        precondition(
            pages.filter { $0.image != nil }.count <= Self.maximumDecodedPageCount,
            "continuous reading must keep a bounded decoded window"
        )
        let previousID = self.currentItemID
        let previousFrame = previousID.flatMap(document.frame(for:))
        let previousOffsetFromPage = previousFrame.map {
            scrollView.contentView.bounds.minY - $0.minY
        }
        let shouldRevealCurrent = previousID != currentItemID
        isApplyingPages = true
        self.currentItemID = currentItemID
        document.pages = pages
        needsLayout = true
        layoutSubtreeIfNeeded()
        if shouldRevealCurrent, let currentItemID,
           let frame = document.frame(for: currentItemID) {
            scroll(toDocumentY: frame.minY - 12)
        } else if let currentItemID,
                  let previousOffsetFromPage,
                  let frame = document.frame(for: currentItemID) {
            scroll(toDocumentY: frame.minY + previousOffsetFromPage)
        }
        isApplyingPages = false
    }

    func testingScrollToItem(with id: ImageItem.ID) {
        guard let frame = document.frame(for: id) else { return }
        scroll(toDocumentY: frame.midY - scrollView.contentSize.height / 2)
        publishFocusedItemIfNeeded()
    }

    private func scroll(toDocumentY y: CGFloat) {
        let maximumY = max(0, document.bounds.height - scrollView.contentSize.height)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: min(max(0, y), maximumY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func scheduleFocusUpdate() {
        guard !isApplyingPages else { return }
        focusUpdateTimer?.invalidate()
        focusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishFocusedItemIfNeeded() }
        }
    }

    private func publishFocusedItemIfNeeded() {
        guard !isApplyingPages,
              let focusedID = document.nearestItemID(toDocumentY: scrollView.contentView.bounds.midY),
              focusedID != currentItemID else { return }
        currentItemID = focusedID
        onFocusedItemChanged?(focusedID)
    }
}

private final class ContinuousReadingClipView: NSClipView {
    var onBoundsOriginChanged: (() -> Void)?

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        let didChange = bounds.origin != newOrigin
        super.setBoundsOrigin(newOrigin)
        if didChange { onBoundsOriginChanged?() }
    }
}

private final class ContinuousReadingDocumentView: NSView {
    var pages: [ContinuousReadingPage] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        pageFrames(for: width).last?.maxY ?? 0
    }

    func frame(for itemID: ImageItem.ID) -> CGRect? {
        zip(pages, pageFrames(for: bounds.width)).first { $0.0.item.id == itemID }?.1
    }

    func nearestItemID(toDocumentY y: CGFloat) -> ImageItem.ID? {
        zip(pages, pageFrames(for: bounds.width))
            .min { abs($0.1.midY - y) < abs($1.1.midY - y) }?
            .0.item.id
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
        for (page, frame) in zip(pages, pageFrames(for: bounds.width)) where frame.intersects(dirtyRect) {
            guard let image = page.image else {
                NSColor.windowBackgroundColor.withAlphaComponent(0.18).setFill()
                frame.fill()
                continue
            }
            NSImage(cgImage: image.cgImage, size: frame.size).draw(
                in: frame,
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
    }

    private func pageFrames(for width: CGFloat) -> [CGRect] {
        let horizontalInset: CGFloat = 16
        let gap: CGFloat = 18
        let contentWidth = max(width - horizontalInset * 2, 1)
        var y: CGFloat = 16
        return pages.map { page in
            let aspectHeight: CGFloat
            if let image = page.image, image.cgImage.width > 0 {
                aspectHeight = contentWidth * CGFloat(image.cgImage.height) / CGFloat(image.cgImage.width)
            } else {
                aspectHeight = min(contentWidth * 0.75, 420)
            }
            let frame = CGRect(x: horizontalInset, y: y, width: contentWidth, height: max(aspectHeight, 1))
            y = frame.maxY + gap
            return frame
        }
    }
}
