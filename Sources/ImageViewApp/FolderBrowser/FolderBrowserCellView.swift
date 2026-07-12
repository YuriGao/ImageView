import AppKit
import ImageViewCore

final class FolderBrowserCellView: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FolderBrowserCellView")

    private let thumbnailView = NSImageView()
    private let filenameField = NSTextField(labelWithString: "")
    private var thumbnailRequest: ThumbnailRequest?
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

    func configure(with item: ImageItem, thumbnailProvider: ThumbnailProvider) {
        thumbnailRequest?.cancel()
        representedObject = item
        filenameField.stringValue = item.url.deletingPathExtension().lastPathComponent
        thumbnailView.image = nil

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
    }
}

private final class FolderBrowserAppearanceTrackingView: NSView {
    var onEffectiveAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChanged?()
    }
}
