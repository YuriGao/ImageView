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
    var onClearFilters: (() -> Void)?
    var onRetryFolder: (() -> Void)?
    var onChooseAnotherFolder: (() -> Void)?
    var onCancelOperation: (() -> Void)?
    var onUndoLastOperation: (() -> Void)?
    var onShowOperationDetails: ((String) -> Void)?
    var onAccessibilityAnnouncementForTesting: ((String) -> Void)?

    private let thumbnailProvider: ThumbnailProvider
    private var items: [ImageItem] = []
    private var itemIndexPathsByID: [ImageItem.ID: IndexPath] = [:]

    private let searchField = NSSearchField()
    private let sortPopUpButton = NSPopUpButton()
    private let typeFilterPopUpButton = NSPopUpButton()
    private let trashButton = NSButton(title: AppStrings.text("folderBrowser.button.trash"), target: nil, action: nil)
    private let moveButton = NSButton(title: AppStrings.text("folderBrowser.button.move"), target: nil, action: nil)
    private let renameButton = NSButton(title: AppStrings.text("folderBrowser.button.rename"), target: nil, action: nil)
    private let batchMoreButton = NSButton()
    private let toolbar = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private let operationStatusLabel = NSTextField(labelWithString: "")
    private let undoOperationButton = NSButton()
    private let operationDetailsButton = NSButton()
    private let operationActionsStack = NSStackView()
    private let operationProgressIndicator = NSProgressIndicator()
    private let operationProgressLabel = NSTextField(labelWithString: "")
    private let cancelOperationButton = NSButton()
    private let operationProgressStack = NSStackView()
    private let collectionView = ReturnOpeningCollectionView()
    private let collectionScrollView = NSScrollView()
    private let stateProgressIndicator = NSProgressIndicator()
    private let stateTitleLabel = NSTextField(labelWithString: "")
    private let stateMessageLabel = NSTextField(wrappingLabelWithString: "")
    private let primaryRecoveryButton = NSButton()
    private let secondaryRecoveryButton = NSButton()
    private let stateStack = NSStackView()
    private var primaryRecoveryAction: RecoveryAction?
    private var secondaryRecoveryAction: RecoveryAction?
    private var currentPresentation: FolderBrowserPresentation = .content
    private var currentIsOperating = false
    private var isCompactToolbar = false
    private var lastAnnouncedVisibleCount: Int?
    private var operationDetailsText: String?

    var testingSearchPlaceholder: String? { searchField.placeholderString }
    var testingSearchText: String { searchField.stringValue }
    var testingSelectedTypeFilterTag: Int { typeFilterPopUpButton.selectedTag() }
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
    var testingUndoOperationVisible: Bool { !undoOperationButton.isHidden }
    var testingOperationDetailsVisible: Bool { !operationDetailsButton.isHidden }
    var testingCountText: String { countLabel.stringValue }
    var testingSearchWidthRange: ClosedRange<CGFloat> { 220...420 }
    var testingProgressText: String? {
        operationProgressStack.isHidden ? nil : operationProgressLabel.stringValue
    }
    var testingCancelVisible: Bool { !operationProgressStack.isHidden && !cancelOperationButton.isHidden }
    var testingIsCompactToolbar: Bool { isCompactToolbar }
    var testingHasBatchMoreButton: Bool { batchMoreButton.superview != nil && !batchMoreButton.isHidden }
    var testingBatchActionButtonsDisabled: Bool {
        !trashButton.isEnabled && !moveButton.isEnabled && !renameButton.isEnabled
    }
    var testingItemCount: Int { collectionView.numberOfItems(inSection: 0) }
    var testingSelectedIDs: Set<ImageItem.ID> {
        Set(collectionView.selectionIndexPaths.compactMap { item(at: $0)?.id })
    }
    var testingReloadCount: Int { collectionView.reloadCount }
    var testingPresentationTitle: String? { stateStack.isHidden ? nil : stateTitleLabel.stringValue }
    var testingPresentationMessage: String? { stateStack.isHidden ? nil : stateMessageLabel.stringValue }
    var testingIsProgressVisible: Bool { !stateStack.isHidden && !stateProgressIndicator.isHidden }
    var testingVisibleRecoveryButtonTitles: [String] {
        [primaryRecoveryButton, secondaryRecoveryButton]
            .filter { !$0.isHidden }
            .map(\.title)
    }
    var testingIsCollectionVisible: Bool { !collectionScrollView.isHidden }
    var testingScrollOrigin: NSPoint { collectionScrollView.contentView.bounds.origin }
    var testingDoubleClickRecognizerCount: Int {
        collectionView.gestureRecognizers.count {
            ($0 as? NSClickGestureRecognizer)?.numberOfClicksRequired == 2
        }
    }
    var testingDoubleClickDelaysPrimaryMouseButtonEvents: Bool? {
        collectionView.gestureRecognizers
            .compactMap { $0 as? NSClickGestureRecognizer }
            .first { $0.numberOfClicksRequired == 2 }?
            .delaysPrimaryMouseButtonEvents
    }

    func testingCell(at index: Int) -> FolderBrowserCellView? {
        guard index >= 0, index < items.count else { return nil }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.layoutSubtreeIfNeeded()
        return collectionView.item(at: indexPath) as? FolderBrowserCellView
    }

    func testingSetScrollOrigin(_ origin: NSPoint) {
        collectionScrollView.contentView.scroll(to: origin)
        collectionScrollView.reflectScrolledClipView(collectionScrollView.contentView)
    }

    func testingPerformDoubleClick(onItemAt index: Int) {
        openItem(at: IndexPath(item: index, section: 0))
    }

    func testingPerformDoubleClickOnBlankSpace() {
        openItem(at: nil)
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

    override func layout() {
        super.layout()
        updateResponsiveToolbar()
    }

    func apply(items: [ImageItem], selectedIDs: Set<ImageItem.ID>) {
        applyItems(items)
        applySelection(selectedIDs)
    }

    func applyItems(_ newItems: [ImageItem]) {
        guard items != newItems else { return }
        items = newItems
        itemIndexPathsByID = Dictionary(
            uniqueKeysWithValues: newItems.enumerated().map { index, item in
                (item.id, IndexPath(item: index, section: 0))
            }
        )
        collectionView.reloadData()
        updateBatchActionAvailability()
    }

    func applySelection(_ selectedIDs: Set<ImageItem.ID>) {
        let indexPaths = Set(selectedIDs.compactMap { itemIndexPathsByID[$0] })
        guard collectionView.selectionIndexPaths != indexPaths else {
            updateBatchActionAvailability()
            return
        }
        collectionView.selectionIndexPaths = indexPaths
        updateBatchActionAvailability()
    }

    func applyCounts(total: Int, visible: Int, selected: Int) {
        var parts = [String(format: AppStrings.text("folderBrowser.count.total"), total)]
        if visible != total {
            parts.append(String(format: AppStrings.text("folderBrowser.count.filtered"), visible))
        }
        if selected > 0 {
            parts.append(String(format: AppStrings.text("folderBrowser.count.selected"), selected))
        }
        countLabel.stringValue = parts.joined(separator: " · ")
        countLabel.setAccessibilityValue(countLabel.stringValue)
        if let previous = lastAnnouncedVisibleCount, previous != visible {
            announce(String(format: AppStrings.text("folderBrowser.announcement.filtered"), visible))
        }
        lastAnnouncedVisibleCount = visible
    }

    func applyFilter(_ filter: FolderFilter) {
        applySearchText(filter.searchText)
        applyTypeFilter(filter.allowedFormats)
    }

    func applySearchText(_ searchText: String) {
        searchField.stringValue = searchText
    }

    func applyTypeFilter(_ allowedFormats: Set<SupportedImageFormat>) {
        if allowedFormats.count == 1,
           let format = allowedFormats.first,
           let index = SupportedImageFormat.allCases.firstIndex(of: format) {
            typeFilterPopUpButton.selectItem(withTag: index)
        } else {
            typeFilterPopUpButton.selectItem(withTag: -1)
        }
    }

    func applyPresentation(_ presentation: FolderBrowserPresentation) {
        currentPresentation = presentation
        collectionScrollView.isHidden = presentation != .content
        stateStack.isHidden = presentation == .content
        stateProgressIndicator.isHidden = presentation != .loading
        primaryRecoveryButton.isHidden = true
        secondaryRecoveryButton.isHidden = true
        primaryRecoveryAction = nil
        secondaryRecoveryAction = nil

        switch presentation {
        case .loading:
            stateTitleLabel.stringValue = AppStrings.text("folderBrowser.state.loading.title")
            stateMessageLabel.stringValue = AppStrings.text("folderBrowser.state.loading.message")
            stateProgressIndicator.startAnimation(nil)
        case .content:
            stateProgressIndicator.stopAnimation(nil)
            stateTitleLabel.stringValue = ""
            stateMessageLabel.stringValue = ""
        case .emptyFolder:
            configureState(
                titleKey: "folderBrowser.state.emptyFolder.title",
                messageKey: "folderBrowser.state.emptyFolder.message",
                primaryTitleKey: "folderBrowser.button.chooseAnotherFolder",
                primaryAction: .chooseAnotherFolder
            )
        case .filteredEmpty:
            configureState(
                titleKey: "folderBrowser.state.filteredEmpty.title",
                messageKey: "folderBrowser.state.filteredEmpty.message",
                primaryTitleKey: "folderBrowser.button.clearFilters",
                primaryAction: .clearFilters
            )
        case .loadFailed(let message):
            stateTitleLabel.stringValue = AppStrings.text("folderBrowser.state.loadFailed.title")
            stateMessageLabel.stringValue = message
            configure(
                primaryRecoveryButton,
                titleKey: "folderBrowser.button.retry",
                action: .retryFolder
            )
            configure(
                secondaryRecoveryButton,
                titleKey: "folderBrowser.button.chooseAnotherFolder",
                action: .chooseAnotherFolder
            )
        }

        if presentation != .loading {
            stateProgressIndicator.stopAnimation(nil)
        }
        updateBatchActionAvailability()
    }

    func applyOperationStatus(
        message: String?,
        failures: [BatchFileFailure],
        recoveryFailures: [BatchRecoveryFailure] = [],
        isOperating: Bool
    ) {
        let wasOperating = currentIsOperating
        currentIsOperating = isOperating
        undoOperationButton.isEnabled = !isOperating && !undoOperationButton.isHidden
        operationDetailsText = detailsText(for: failures, recoveryFailures: recoveryFailures)
        operationDetailsButton.isHidden = operationDetailsText == nil
        operationDetailsButton.isEnabled = !isOperating
        let failureText = failureSummary(for: failures)
        let recoveryText = recoverySummary(for: recoveryFailures)
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

        let completeStatusText = [statusText, recoveryText]
            .compactMap { $0 }
            .joined(separator: "\n")

        operationStatusLabel.stringValue = completeStatusText
        operationStatusLabel.isHidden = completeStatusText.isEmpty
        if wasOperating && !isOperating && !completeStatusText.isEmpty {
            announce(String(format: AppStrings.text("folderBrowser.announcement.completed"), completeStatusText))
        }
        updateBatchActionAvailability()
    }

    func applyProgress(_ progress: FolderBatchProgress?) {
        guard let progress else {
            operationProgressStack.isHidden = true
            return
        }
        operationProgressStack.isHidden = false
        operationProgressIndicator.minValue = 0
        operationProgressIndicator.maxValue = Double(max(progress.total, 1))
        operationProgressIndicator.doubleValue = Double(progress.processed)
        operationProgressLabel.stringValue = "\(progress.phase) · \(progress.processed) / \(progress.total)"
        operationProgressLabel.setAccessibilityValue(operationProgressLabel.stringValue)
        cancelOperationButton.title = AppStrings.text(
            progress.isCancelling ? "folderBrowser.progress.cancelling" : "folderBrowser.progress.cancel"
        )
        cancelOperationButton.isEnabled = !progress.isCancelling
    }

    func applyUndoAvailability(_ isAvailable: Bool) {
        undoOperationButton.isHidden = !isAvailable
        undoOperationButton.isEnabled = isAvailable && !currentIsOperating
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

    func testingPerformOperationDetailsAction() {
        showOperationDetailsClicked(operationDetailsButton)
    }

    func testingPerformKeyDown(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [],
        characters: String
    ) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else { return }
        collectionView.keyDown(with: event)
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

    func testingTriggerCancelOperation() {
        cancelOperationButton.performClick(nil)
    }

    func testingTriggerPrimaryRecovery() {
        primaryRecoveryButton.performClick(nil)
    }

    func testingTriggerSecondaryRecovery() {
        secondaryRecoveryButton.performClick(nil)
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

        cell.configure(
            with: items[indexPath.item],
            thumbnailProvider: thumbnailProvider,
            position: indexPath.item + 1,
            total: items.count
        )
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
        for button in [moveButton, renameButton, trashButton] {
            button.toolTip = button.title
            button.setAccessibilityLabel(button.title)
        }
        trashButton.contentTintColor = .systemRed
        batchMoreButton.image = NSImage(
            systemSymbolName: "ellipsis.circle",
            accessibilityDescription: AppStrings.text("folderBrowser.button.more")
        )
        batchMoreButton.bezelStyle = .toolbar
        batchMoreButton.isBordered = false
        batchMoreButton.toolTip = AppStrings.text("folderBrowser.button.more")
        batchMoreButton.setAccessibilityLabel(AppStrings.text("folderBrowser.button.more"))
        batchMoreButton.target = self
        batchMoreButton.action = #selector(showBatchMoreMenu(_:))
        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        operationStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        operationStatusLabel.textColor = .secondaryLabelColor
        operationStatusLabel.lineBreakMode = .byWordWrapping
        operationStatusLabel.maximumNumberOfLines = 0
        operationStatusLabel.isHidden = true
        undoOperationButton.title = AppStrings.text("folderBrowser.operation.undo")
        undoOperationButton.translatesAutoresizingMaskIntoConstraints = false
        undoOperationButton.bezelStyle = .rounded
        undoOperationButton.controlSize = .small
        undoOperationButton.target = self
        undoOperationButton.action = #selector(undoOperationClicked(_:))
        undoOperationButton.setAccessibilityLabel(undoOperationButton.title)
        undoOperationButton.isHidden = true
        operationDetailsButton.title = AppStrings.text("folderBrowser.operation.viewDetails")
        operationDetailsButton.bezelStyle = .rounded
        operationDetailsButton.controlSize = .small
        operationDetailsButton.target = self
        operationDetailsButton.action = #selector(showOperationDetailsClicked(_:))
        operationDetailsButton.setAccessibilityLabel(operationDetailsButton.title)
        operationDetailsButton.isHidden = true
        operationActionsStack.setViews([operationDetailsButton, undoOperationButton], in: .leading)
        operationActionsStack.orientation = .horizontal
        operationActionsStack.alignment = .centerY
        operationActionsStack.spacing = 6
        operationActionsStack.translatesAutoresizingMaskIntoConstraints = false
        operationProgressIndicator.style = .bar
        operationProgressIndicator.controlSize = .small
        operationProgressLabel.font = .systemFont(ofSize: 11, weight: .medium)
        operationProgressLabel.textColor = .secondaryLabelColor
        cancelOperationButton.title = AppStrings.text("folderBrowser.progress.cancel")
        cancelOperationButton.bezelStyle = .rounded
        cancelOperationButton.controlSize = .small
        cancelOperationButton.target = self
        cancelOperationButton.action = #selector(cancelOperationClicked(_:))
        operationProgressStack.setViews(
            [operationProgressLabel, operationProgressIndicator, cancelOperationButton],
            in: .leading
        )
        operationProgressStack.orientation = .horizontal
        operationProgressStack.alignment = .centerY
        operationProgressStack.spacing = 8
        operationProgressStack.translatesAutoresizingMaskIntoConstraints = false
        operationProgressStack.isHidden = true
        operationProgressIndicator.widthAnchor.constraint(equalToConstant: 140).isActive = true

        toolbar.setViews([
            searchField,
            sortPopUpButton,
            typeFilterPopUpButton,
            moveButton,
            renameButton,
            trashButton,
            batchMoreButton
        ], in: .leading)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        batchMoreButton.isHidden = true
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        operationStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false

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
        collectionView.selectAllItems = { [weak self] in
            self?.selectAllVisibleItems()
        }
        collectionView.deleteSelectedItems = { [weak self] in
            guard let self, !self.collectionView.selectionIndexPaths.isEmpty else { return }
            self.onMoveToTrash?()
        }
        let doubleClickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(openSelectedItem(_:)))
        doubleClickRecognizer.numberOfClicksRequired = 2
        doubleClickRecognizer.delaysPrimaryMouseButtonEvents = false
        collectionView.addGestureRecognizer(doubleClickRecognizer)

        collectionScrollView.translatesAutoresizingMaskIntoConstraints = false
        collectionScrollView.hasVerticalScroller = true
        collectionScrollView.documentView = collectionView

        stateProgressIndicator.style = .spinning
        stateProgressIndicator.controlSize = .regular
        stateTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        stateTitleLabel.alignment = .center
        stateMessageLabel.textColor = .secondaryLabelColor
        stateMessageLabel.alignment = .center
        stateMessageLabel.maximumNumberOfLines = 3
        primaryRecoveryButton.bezelStyle = .rounded
        primaryRecoveryButton.keyEquivalent = "\r"
        primaryRecoveryButton.target = self
        primaryRecoveryButton.action = #selector(primaryRecoveryClicked(_:))
        secondaryRecoveryButton.bezelStyle = .rounded
        secondaryRecoveryButton.target = self
        secondaryRecoveryButton.action = #selector(secondaryRecoveryClicked(_:))
        let recoveryButtons = NSStackView(views: [primaryRecoveryButton, secondaryRecoveryButton])
        recoveryButtons.orientation = .horizontal
        recoveryButtons.alignment = .centerY
        recoveryButtons.spacing = 8

        stateStack.setViews(
            [stateProgressIndicator, stateTitleLabel, stateMessageLabel, recoveryButtons],
            in: .center
        )
        stateStack.translatesAutoresizingMaskIntoConstraints = false
        stateStack.orientation = .vertical
        stateStack.alignment = .centerX
        stateStack.spacing = 10
        stateStack.isHidden = true
        stateProgressIndicator.isHidden = true
        primaryRecoveryButton.isHidden = true
        secondaryRecoveryButton.isHidden = true

        addSubview(toolbar)
        addSubview(countLabel)
        addSubview(operationStatusLabel)
        addSubview(operationActionsStack)
        addSubview(operationProgressStack)
        addSubview(collectionScrollView)
        addSubview(stateStack)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            countLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            operationStatusLabel.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 4),
            operationStatusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            operationStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: operationActionsStack.leadingAnchor, constant: -8),
            operationActionsStack.centerYAnchor.constraint(equalTo: operationStatusLabel.centerYAnchor),
            operationActionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            operationProgressStack.topAnchor.constraint(equalTo: operationStatusLabel.bottomAnchor, constant: 4),
            operationProgressStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            operationProgressStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            collectionScrollView.topAnchor.constraint(equalTo: operationProgressStack.bottomAnchor, constant: 8),
            collectionScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stateStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stateStack.centerYAnchor.constraint(equalTo: collectionScrollView.centerYAnchor),
            stateStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stateStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
            stateMessageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
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

    @objc private func trashClicked(_ sender: Any?) {
        onMoveToTrash?()
    }

    @objc private func moveClicked(_ sender: Any?) {
        onMoveToFolder?()
    }

    @objc private func renameClicked(_ sender: Any?) {
        onBatchRename?()
    }

    @objc private func cancelOperationClicked(_ sender: NSButton) {
        onCancelOperation?()
    }

    @objc private func undoOperationClicked(_ sender: NSButton) {
        onUndoLastOperation?()
    }

    @objc private func showOperationDetailsClicked(_ sender: NSButton) {
        guard let operationDetailsText else { return }
        onShowOperationDetails?(operationDetailsText)
    }

    @objc private func showBatchMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let rename = NSMenuItem(
            title: renameButton.title,
            action: #selector(renameClicked(_:)),
            keyEquivalent: ""
        )
        rename.target = self
        rename.isEnabled = renameButton.isEnabled
        menu.addItem(rename)
        menu.addItem(.separator())
        let trash = NSMenuItem(
            title: trashButton.title,
            action: #selector(trashClicked(_:)),
            keyEquivalent: ""
        )
        trash.target = self
        trash.isEnabled = trashButton.isEnabled
        menu.addItem(trash)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    private func updateResponsiveToolbar() {
        let compact = bounds.width > 0 && bounds.width < 900
        guard compact != isCompactToolbar else { return }
        isCompactToolbar = compact
        renameButton.isHidden = compact
        trashButton.isHidden = compact
        batchMoreButton.isHidden = !compact
    }

    private func announce(_ message: String) {
        if let onAccessibilityAnnouncementForTesting {
            onAccessibilityAnnouncementForTesting(message)
            return
        }
        NSAccessibility.post(
            element: NSApp!,
            notification: .announcementRequested,
            userInfo:
            [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    @objc private func primaryRecoveryClicked(_ sender: NSButton) {
        perform(primaryRecoveryAction)
    }

    @objc private func secondaryRecoveryClicked(_ sender: NSButton) {
        perform(secondaryRecoveryAction)
    }

    @objc private func openSelectedItem(_ sender: NSClickGestureRecognizer) {
        let location = sender.location(in: collectionView)
        openItem(at: collectionView.indexPathForItem(at: location))
    }

    private func openItem(at indexPath: IndexPath?) {
        guard let indexPath, let item = item(at: indexPath) else { return }
        collectionView.selectionIndexPaths = [indexPath]
        onOpenItem?(item)
    }

    private func openFirstSelectedItem() {
        guard let indexPath = collectionView.selectionIndexPaths.sorted().first,
              let item = item(at: indexPath) else {
            return
        }
        onOpenItem?(item)
    }

    private func selectAllVisibleItems() {
        let indexPaths = Set(items.indices.map { IndexPath(item: $0, section: 0) })
        collectionView.selectionIndexPaths = indexPaths
        onSelectionChanged?(Set(items.map(\.id)))
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

    private func detailsText(
        for failures: [BatchFileFailure],
        recoveryFailures: [BatchRecoveryFailure]
    ) -> String? {
        let failureLines = failures.map {
            "\($0.url.lastPathComponent): \(failureReasonText($0.reason))"
        }
        let recoveryText = recoverySummary(for: recoveryFailures)
        let sections = [failureLines.isEmpty ? nil : failureLines.joined(separator: "\n"), recoveryText]
            .compactMap { $0 }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func recoverySummary(for failures: [BatchRecoveryFailure]) -> String? {
        guard !failures.isEmpty else { return nil }
        let heading = AppStrings.text("folderBrowser.recovery.heading")
        let lines = failures.flatMap { failure -> [String] in
            let detail = String(
                format: AppStrings.text("folderBrowser.recovery.item"),
                failure.expectedURL.lastPathComponent,
                failure.actualURL.lastPathComponent,
                failure.reason
            )
            guard failure.actualURL.lastPathComponent.hasPrefix(".batch-rename-"),
                  failure.actualURL.pathExtension == "tmp" else {
                return [detail]
            }
            return [detail, AppStrings.text("folderBrowser.recovery.hiddenTemporaryHint")]
        }
        return ([heading] + lines).joined(separator: "\n")
    }

    private func configureState(
        titleKey: String,
        messageKey: String,
        primaryTitleKey: String,
        primaryAction: RecoveryAction
    ) {
        stateTitleLabel.stringValue = AppStrings.text(titleKey)
        stateMessageLabel.stringValue = AppStrings.text(messageKey)
        configure(primaryRecoveryButton, titleKey: primaryTitleKey, action: primaryAction)
    }

    private func configure(_ button: NSButton, titleKey: String, action: RecoveryAction) {
        button.title = AppStrings.text(titleKey)
        button.isHidden = false
        if button === primaryRecoveryButton {
            primaryRecoveryAction = action
        } else {
            secondaryRecoveryAction = action
        }
    }

    private func perform(_ action: RecoveryAction?) {
        switch action {
        case .clearFilters:
            onClearFilters?()
        case .retryFolder:
            onRetryFolder?()
        case .chooseAnotherFolder:
            onChooseAnotherFolder?()
        case nil:
            break
        }
    }

    private func updateBatchActionAvailability() {
        let enabled = currentPresentation == .content && !currentIsOperating && !collectionView.selectionIndexPaths.isEmpty
        for button in [trashButton, moveButton, renameButton] {
            button.isEnabled = enabled
        }
        batchMoreButton.isEnabled = enabled
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
        case .cancelled:
            return AppStrings.text("folderBrowser.failure.cancelled")
        }
    }
}

private enum RecoveryAction {
    case clearFilters
    case retryFolder
    case chooseAnotherFolder
}

private final class ReturnOpeningCollectionView: NSCollectionView {
    var openSelectedItem: (() -> Void)?
    var selectAllItems: (() -> Void)?
    var deleteSelectedItems: (() -> Void)?
    private(set) var reloadCount = 0

    override func reloadData() {
        reloadCount += 1
        super.reloadData()
    }

    override func keyDown(with event: NSEvent) {
        let ignoredModifiers: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(ignoredModifiers)
        if event.keyCode == 0, modifiers == .command {
            selectAllItems?()
        } else if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelectedItems?()
        } else if event.keyCode == 36 {
            openSelectedItem?()
        } else {
            super.keyDown(with: event)
        }
    }
}
