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
    private let trashButton = NSButton(title: AppStrings.text("folderBrowser.button.trash"), target: nil, action: nil)
    private let moveButton = NSButton(title: AppStrings.text("folderBrowser.button.move"), target: nil, action: nil)
    private let renameButton = NSButton(title: AppStrings.text("folderBrowser.button.rename"), target: nil, action: nil)
    private let operationStatusLabel = NSTextField(labelWithString: "")
    private let collectionView = ReturnOpeningCollectionView()

    var testingSearchPlaceholder: String? { searchField.placeholderString }
    var testingHasSortControl: Bool { sortPopUpButton.superview != nil }
    var testingHasTypeFilterControl: Bool { typeFilterPopUpButton.superview != nil }
    var testingHasTrashButton: Bool { trashButton.superview != nil }
    var testingHasMoveButton: Bool { moveButton.superview != nil }
    var testingHasRenameButton: Bool { renameButton.superview != nil }
    var testingHasCollectionView: Bool { collectionView.enclosingScrollView?.superview != nil }
    var testingTrashButtonTitle: String { trashButton.title }
    var testingMoveButtonTitle: String { moveButton.title }
    var testingRenameButtonTitle: String { renameButton.title }
    var testingOperationStatusText: String? {
        operationStatusLabel.isHidden ? nil : operationStatusLabel.stringValue
    }
    var testingBatchActionButtonsDisabled: Bool {
        !trashButton.isEnabled && !moveButton.isEnabled && !renameButton.isEnabled
    }
    var testingItemCount: Int { collectionView.numberOfItems(inSection: 0) }
    var testingSelectedIDs: Set<ImageItem.ID> {
        Set(collectionView.selectionIndexPaths.compactMap { item(at: $0)?.id })
    }

    func testingCell(at index: Int) -> FolderBrowserCellView? {
        guard index >= 0, index < items.count else { return nil }
        let indexPath = IndexPath(item: index, section: 0)
        if let cell = collectionView.item(at: indexPath) as? FolderBrowserCellView {
            return cell
        }
        return collectionView(
            collectionView,
            itemForRepresentedObjectAt: indexPath
        ) as? FolderBrowserCellView
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
        applyItems(items)
        applySelection(selectedIDs)
    }

    func applyItems(_ newItems: [ImageItem]) {
        guard items != newItems else { return }
        items = newItems
        collectionView.reloadData()
    }

    func applySelection(_ selectedIDs: Set<ImageItem.ID>) {
        let indexPaths = Set(items.enumerated().compactMap { index, item in
            selectedIDs.contains(item.id) ? IndexPath(item: index, section: 0) : nil
        })
        guard collectionView.selectionIndexPaths != indexPaths else { return }
        collectionView.selectionIndexPaths = indexPaths
    }

    func applyOperationStatus(message: String?, failures: [BatchFileFailure], isOperating: Bool) {
        let failureText = failureSummary(for: failures)
        let statusText: String?
        switch (isOperating, message, failureText) {
        case (true, let message?, let failureText?):
            statusText = "\(AppStrings.text("folderBrowser.status.working")) \(message) · \(failureText)"
        case (true, let message?, nil):
            statusText = "\(AppStrings.text("folderBrowser.status.working")) \(message)"
        case (true, nil, let failureText?):
            statusText = "\(AppStrings.text("folderBrowser.status.working")) \(failureText)"
        case (true, nil, nil):
            statusText = AppStrings.text("folderBrowser.status.working")
        case (false, let message?, let failureText?):
            statusText = "\(message) · \(failureText)"
        case (false, let message?, nil):
            statusText = message
        case (false, nil, let failureText?):
            statusText = failureText
        case (false, nil, nil):
            statusText = nil
        }

        operationStatusLabel.stringValue = statusText ?? ""
        operationStatusLabel.isHidden = statusText == nil
        for button in [trashButton, moveButton, renameButton] {
            button.isEnabled = !isOperating
        }
    }

    func testingSelectItems(with ids: Set<ImageItem.ID>) {
        let indexPaths = Set(items.enumerated().compactMap { index, item in
            ids.contains(item.id) ? IndexPath(item: index, section: 0) : nil
        })
        collectionView.selectionIndexPaths = indexPaths
        collectionView(collectionView, didSelectItemsAt: indexPaths)
    }

    func testingPerformOpenAction() {
        collectionView.openSelectedItem?()
    }

    func testingSetSearchText(_ text: String) {
        searchField.stringValue = text
        searchChanged(searchField)
    }

    func testingSetSortMode(_ sortMode: FolderSortMode) {
        sortPopUpButton.selectItem(withTag: tag(for: sortMode))
        sortChanged(sortPopUpButton)
    }

    func testingSelectTypeFilterPopupItem(_ format: SupportedImageFormat) {
        guard let index = SupportedImageFormat.allCases.firstIndex(of: format) else {
            return
        }
        typeFilterPopUpButton.selectItem(withTag: index)
        typeFilterChanged(typeFilterPopUpButton)
    }

    func testingSelectAllTypesFilterPopupItem() {
        typeFilterPopUpButton.selectItem(withTag: -1)
        typeFilterChanged(typeFilterPopUpButton)
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

        searchField.placeholderString = AppStrings.text("folderBrowser.searchPlaceholder")
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))

        sortPopUpButton.addItem(withTitle: AppStrings.text("folderBrowser.sort.name"))
        sortPopUpButton.lastItem?.tag = tag(for: .nameAscending)
        sortPopUpButton.addItem(withTitle: AppStrings.text("folderBrowser.sort.modified"))
        sortPopUpButton.lastItem?.tag = tag(for: .modifiedDateDescending)
        sortPopUpButton.addItem(withTitle: AppStrings.text("folderBrowser.sort.size"))
        sortPopUpButton.lastItem?.tag = tag(for: .fileSizeDescending)
        sortPopUpButton.target = self
        sortPopUpButton.action = #selector(sortChanged(_:))

        typeFilterPopUpButton.addItem(withTitle: AppStrings.text("folderBrowser.typeFilter.all"))
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
        operationStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        operationStatusLabel.textColor = .secondaryLabelColor
        operationStatusLabel.lineBreakMode = .byTruncatingTail
        operationStatusLabel.isHidden = true

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
        operationStatusLabel.translatesAutoresizingMaskIntoConstraints = false

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
        addSubview(operationStatusLabel)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            operationStatusLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            operationStatusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            operationStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: operationStatusLabel.bottomAnchor, constant: 8),
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

    private func failureSummary(for failures: [BatchFileFailure]) -> String? {
        guard let firstFailure = failures.first else { return nil }
        let countKey = failures.count == 1 ? "folderBrowser.status.failure.one" : "folderBrowser.status.failure.other"
        let countText = String(format: AppStrings.text(countKey), failures.count)
        return "\(countText) · \(firstFailure.url.lastPathComponent): \(failureReasonText(firstFailure.reason))"
    }

    private func failureReasonText(_ reason: BatchFileFailureReason) -> String {
        switch reason {
        case .emptyName:
            return AppStrings.text("folderBrowser.failure.emptyName")
        case .invalidName:
            return AppStrings.text("folderBrowser.failure.invalidName")
        case .sourceMissing:
            return AppStrings.text("folderBrowser.failure.sourceMissing")
        case .destinationExists:
            return AppStrings.text("folderBrowser.failure.destinationExists")
        case .duplicateDestination:
            return AppStrings.text("folderBrowser.failure.duplicateDestination")
        case .trashFailed(let detail):
            return String(format: AppStrings.text("folderBrowser.failure.trashFailed"), detail)
        case .moveFailed(let detail):
            return String(format: AppStrings.text("folderBrowser.failure.moveFailed"), detail)
        case .renameFailed(let detail):
            return String(format: AppStrings.text("folderBrowser.failure.renameFailed"), detail)
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
