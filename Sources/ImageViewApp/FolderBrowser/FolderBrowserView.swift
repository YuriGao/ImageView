import AppKit
import ImageViewCore

final class FolderBrowserView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onOpenItem: ((ImageItem) -> Void)?
    var onSelectionChanged: ((Set<ImageItem.ID>) -> Void)?
    var onSearchChanged: ((String) -> Void)?
    var onSortChanged: ((FolderSortMode) -> Void)?
    var onTypeFilterChanged: ((Set<SupportedImageFormat>) -> Void)?
    var onMoveToTrash: (() -> Void)?
    var onMoveToFolder: (() -> Void)?
    var onBatchRename: (() -> Void)?

    private let thumbnailProvider: ThumbnailProvider
    private var items: [ImageItem] = []

    private let searchField = NSSearchField()
    private let sortPopUpButton = NSPopUpButton()
    private let typeFilterPopUpButton = NSPopUpButton()
    private let trashButton = NSButton(title: "Trash", target: nil, action: nil)
    private let moveButton = NSButton(title: "Move", target: nil, action: nil)
    private let renameButton = NSButton(title: "Rename", target: nil, action: nil)
    private let collectionView = ReturnOpeningCollectionView()

    var testingSearchPlaceholder: String? { searchField.placeholderString }
    var testingHasSortControl: Bool { sortPopUpButton.superview != nil }
    var testingHasTypeFilterControl: Bool { typeFilterPopUpButton.superview != nil }
    var testingHasTrashButton: Bool { trashButton.superview != nil }
    var testingHasMoveButton: Bool { moveButton.superview != nil }
    var testingHasRenameButton: Bool { renameButton.superview != nil }
    var testingHasCollectionView: Bool { collectionView.enclosingScrollView?.superview != nil }
    var testingItemCount: Int { collectionView.numberOfItems(inSection: 0) }
    var testingSelectedIDs: Set<ImageItem.ID> {
        Set(collectionView.selectionIndexPaths.compactMap { item(at: $0)?.id })
    }

    init(thumbnailProvider: ThumbnailProvider = ThumbnailProvider()) {
        self.thumbnailProvider = thumbnailProvider
        super.init(frame: .zero)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(items: [ImageItem], selectedIDs: Set<ImageItem.ID>) {
        self.items = items
        collectionView.reloadData()

        let indexPaths = Set(items.enumerated().compactMap { index, item in
            selectedIDs.contains(item.id) ? IndexPath(item: index, section: 0) : nil
        })
        collectionView.selectionIndexPaths = indexPaths
    }

    func testingSelectItems(with ids: Set<ImageItem.ID>) {
        let indexPaths = Set(items.enumerated().compactMap { index, item in
            ids.contains(item.id) ? IndexPath(item: index, section: 0) : nil
        })
        collectionView.selectionIndexPaths = indexPaths
        collectionView(collectionView, didSelectItemsAt: indexPaths)
    }

    func testingOpenItem(with id: ImageItem.ID) {
        guard let item = items.first(where: { $0.id == id }) else {
            return
        }
        onOpenItem?(item)
    }

    func testingSetSearchText(_ text: String) {
        searchField.stringValue = text
        searchChanged(searchField)
    }

    func testingSetSortMode(_ sortMode: FolderSortMode) {
        sortPopUpButton.selectItem(withTag: tag(for: sortMode))
        sortChanged(sortPopUpButton)
    }

    func testingSetTypeFilter(_ formats: Set<SupportedImageFormat>) {
        onTypeFilterChanged?(formats)
    }

    func testingTriggerTrash() {
        trashButton.performClick(nil)
    }

    func testingTriggerMove() {
        moveButton.performClick(nil)
    }

    func testingTriggerRename() {
        renameButton.performClick(nil)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: FolderBrowserCellView.reuseIdentifier,
            for: indexPath
        )
        guard let cell = item as? FolderBrowserCellView else {
            return item
        }

        cell.configure(with: items[indexPath.item], thumbnailProvider: thumbnailProvider)
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        onSelectionChanged?(selectedIDs(from: collectionView.selectionIndexPaths))
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        onSelectionChanged?(selectedIDs(from: collectionView.selectionIndexPaths))
    }

    private func buildView() {
        translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search images"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))

        sortPopUpButton.addItem(withTitle: "Name")
        sortPopUpButton.lastItem?.tag = tag(for: .nameAscending)
        sortPopUpButton.addItem(withTitle: "Modified")
        sortPopUpButton.lastItem?.tag = tag(for: .modifiedDateDescending)
        sortPopUpButton.addItem(withTitle: "Size")
        sortPopUpButton.lastItem?.tag = tag(for: .fileSizeDescending)
        sortPopUpButton.target = self
        sortPopUpButton.action = #selector(sortChanged(_:))

        typeFilterPopUpButton.addItem(withTitle: "All Types")
        typeFilterPopUpButton.lastItem?.tag = -1
        for (index, format) in SupportedImageFormat.allCases.enumerated() {
            typeFilterPopUpButton.addItem(withTitle: format.rawValue.uppercased())
            typeFilterPopUpButton.lastItem?.tag = index
        }
        typeFilterPopUpButton.target = self
        typeFilterPopUpButton.action = #selector(typeFilterChanged(_:))

        trashButton.target = self
        trashButton.action = #selector(trashClicked(_:))
        moveButton.target = self
        moveButton.action = #selector(moveClicked(_:))
        renameButton.target = self
        renameButton.action = #selector(renameClicked(_:))

        let toolbar = NSStackView(views: [
            searchField,
            sortPopUpButton,
            typeFilterPopUpButton,
            trashButton,
            moveButton,
            renameButton
        ])
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 148, height: 168)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 14
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.windowBackgroundColor]
        collectionView.register(FolderBrowserCellView.self, forItemWithIdentifier: FolderBrowserCellView.reuseIdentifier)
        collectionView.openSelectedItem = { [weak self] in
            self?.openFirstSelectedItem()
        }
        let doubleClickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(openSelectedItem(_:)))
        doubleClickRecognizer.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClickRecognizer)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = collectionView

        addSubview(toolbar)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        onSearchChanged?(sender.stringValue)
    }

    @objc private func sortChanged(_ sender: NSPopUpButton) {
        onSortChanged?(sortMode(for: sender.selectedTag()))
    }

    @objc private func typeFilterChanged(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        guard tag >= 0, tag < SupportedImageFormat.allCases.count else {
            onTypeFilterChanged?(Set(SupportedImageFormat.allCases))
            return
        }
        onTypeFilterChanged?([SupportedImageFormat.allCases[tag]])
    }

    @objc private func trashClicked(_ sender: NSButton) {
        onMoveToTrash?()
    }

    @objc private func moveClicked(_ sender: NSButton) {
        onMoveToFolder?()
    }

    @objc private func renameClicked(_ sender: NSButton) {
        onBatchRename?()
    }

    @objc private func openSelectedItem(_ sender: Any?) {
        openFirstSelectedItem()
    }

    private func openFirstSelectedItem() {
        guard let indexPath = collectionView.selectionIndexPaths.sorted().first,
              let item = item(at: indexPath) else {
            return
        }
        onOpenItem?(item)
    }

    private func selectedIDs(from indexPaths: Set<IndexPath>) -> Set<ImageItem.ID> {
        Set(indexPaths.compactMap { item(at: $0)?.id })
    }

    private func item(at indexPath: IndexPath) -> ImageItem? {
        guard indexPath.section == 0, indexPath.item >= 0, indexPath.item < items.count else {
            return nil
        }
        return items[indexPath.item]
    }

    private func tag(for sortMode: FolderSortMode) -> Int {
        switch sortMode {
        case .nameAscending:
            return 0
        case .modifiedDateDescending:
            return 1
        case .fileSizeDescending:
            return 2
        }
    }

    private func sortMode(for tag: Int) -> FolderSortMode {
        switch tag {
        case 1:
            return .modifiedDateDescending
        case 2:
            return .fileSizeDescending
        default:
            return .nameAscending
        }
    }
}

private final class ReturnOpeningCollectionView: NSCollectionView {
    var openSelectedItem: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            openSelectedItem?()
        } else {
            super.keyDown(with: event)
        }
    }
}
