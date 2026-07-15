import AppKit
import ImageViewCore

final class FolderBrowserCellView: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FolderBrowserCellView")

    private let thumbnailView = NSImageView()
    private let filenameField = NSTextField(labelWithString: "")
    private var thumbnailRequest: ThumbnailRequest?
    private var accessibilityPosition: Int?
    private var accessibilityTotal: Int?
    private(set) var testingAppearanceRefreshCount = 0

    var testingFilename: String {
        filenameField.stringValue
    }

    var testingImage: NSImage? {
        thumbnailView.image
    }

    var testingShowsSelection: Bool {
        view.layer?.borderWidth == 1
    }

    var testingSelectionBackgroundColor: CGColor? {
        view.layer?.backgroundColor
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override func loadView() {
        let appearanceView = FolderBrowserAppearanceTrackingView()
        appearanceView.onEffectiveAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.testingAppearanceRefreshCount += 1
            self.updateSelectionAppearance()
        }
        view = appearanceView
        view.translatesAutoresizingMaskIntoConstraints = false

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 8
        thumbnailView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        filenameField.translatesAutoresizingMaskIntoConstraints = false
        filenameField.alignment = .center
        filenameField.lineBreakMode = .byTruncatingMiddle
        filenameField.maximumNumberOfLines = 2
        filenameField.font = .systemFont(ofSize: 12)

        view.addSubview(thumbnailView)
        view.addSubview(filenameField)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            thumbnailView.heightAnchor.constraint(equalToConstant: 118),

            filenameField.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 6),
            filenameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            filenameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            filenameField.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -6)
        ])

        updateSelectionAppearance()
    }

    func configure(
        with item: ImageItem,
        thumbnailProvider: ThumbnailProvider,
        position: Int? = nil,
        total: Int? = nil
    ) {
        thumbnailRequest?.cancel()
        representedObject = item
        accessibilityPosition = position
        accessibilityTotal = total
        filenameField.stringValue = item.url.deletingPathExtension().lastPathComponent
        thumbnailView.image = nil
        updateAccessibility()

        thumbnailRequest = thumbnailProvider.loadThumbnail(for: item) { [weak self, itemID = item.id] result in
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let currentItem = self.representedObject as? ImageItem,
                      currentItem.id == itemID else {
                    return
                }

                if case let .success(image) = result {
                    self.thumbnailView.image = image
                }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailRequest?.cancel()
        thumbnailRequest = nil
        representedObject = nil
        accessibilityPosition = nil
        accessibilityTotal = nil
        filenameField.stringValue = ""
        thumbnailView.image = nil
    }

    private func updateSelectionAppearance() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16).cgColor
                : NSColor.clear.cgColor
            view.layer?.borderColor = NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.65).cgColor
        }
        view.layer?.borderWidth = isSelected ? 1 : 0
        filenameField.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        updateAccessibility()
    }

    private func updateAccessibility() {
        guard let item = representedObject as? ImageItem else { return }
        var parts = [item.url.lastPathComponent, item.format.rawValue.uppercased()]
        if let accessibilityPosition, let accessibilityTotal {
            parts.append(String(
                format: AppStrings.text("folderBrowser.item.position"),
                accessibilityPosition,
                accessibilityTotal
            ))
        }
        parts.append(AppStrings.text(isSelected ? "folderBrowser.item.selected" : "folderBrowser.item.notSelected"))
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(parts.joined(separator: ", "))
        view.setAccessibilitySelected(isSelected)
    }
}

private final class FolderBrowserAppearanceTrackingView: NSView {
    var onEffectiveAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChanged?()
    }
}
