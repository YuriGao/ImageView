import AppKit
import Combine
import ImageViewCore
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSGestureRecognizerDelegate {
    static let externalFileCheckInterval: TimeInterval = 2
    static let titleBarHeight: CGFloat = 32
    static let bottomBarHeight: CGFloat = 28
    static let bottomBarInfoSymbolName = "info.circle"
    static let bottomBarStatusToInfoSpacing: CGFloat = 8
    static let filmstripOverlayHeight: CGFloat = 98
    static let overlayAutoHideDelay: TimeInterval = 1.8
    static let overlayFadeOutDuration: TimeInterval = 0.18
    static func titleBarBrowseFolderToolTip(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        AppStrings.text("titleBar.showFolder", preferredLanguages: preferredLanguages)
    }

    var onSuccessfulOpen: ((URL) -> Void)? {
        didSet { viewModel.onSuccessfulOpen = onSuccessfulOpen }
    }
    var onOpenRequested: (() -> Void)?
    var onBrowseFolderRequested: (() -> Void)?
    var onOpenRecentRequested: ((URL) -> Void)?
    var onClearRecentRequested: (() -> Void)?
    private(set) var hasAssignedOpenRequest = false
    var onWindowDidBecomeKey: ((MainWindowController) -> Void)?
    var onWindowDidClose: ((MainWindowController) -> Void)?
    enum MenuCommand: Equatable {
        case fileOperationRequiringCurrentItem
        case navigation
        case canvasSizing
        case startCropping
        case editOperation(EditOperation)
        case saveEdits
        case saveEditsAs
        case discardEdits
        case undoEdit
        case redoEdit
    }

    enum KeyAction: Equatable {
        case showPrevious
        case showNext
        case closeWindow
        case moveToTrash
        case toggleZoom
        case toggleFullscreen
        case startCropping
        case applyCrop
        case cancelCrop
        case endEditing
        case passThrough
    }

    enum UnsavedChangesChoice: Equatable {
        case save
        case discard
        case cancel
    }

    enum UnsavedChangesResolution: Equatable {
        case proceed
        case stayOnCurrentImage
    }

    enum MoveConflictChoice: Equatable {
        case skipConflicts
        case keepBoth
        case cancel
    }

    struct BatchActionDialogProvider {
        var confirmTrash: ((Int) -> Bool)?
        var chooseDestinationFolder: (() -> URL?)?
        var chooseMoveConflict: (([String]) -> MoveConflictChoice)?
        var requestRenameParameters: ((
            [ImageItem],
            BatchRenameSheetController.PlanRename,
            @escaping (BatchRenameSheetController.RenameParameters, BatchRenamePlan) -> Void
        ) -> Void)?

        init(
            confirmTrash: ((Int) -> Bool)? = nil,
            chooseDestinationFolder: (() -> URL?)? = nil,
            chooseMoveConflict: (([String]) -> MoveConflictChoice)? = nil,
            requestRenameParameters: ((
                [ImageItem],
                BatchRenameSheetController.PlanRename,
                @escaping (BatchRenameSheetController.RenameParameters, BatchRenamePlan) -> Void
            ) -> Void)? = nil
        ) {
            self.confirmTrash = confirmTrash
            self.chooseDestinationFolder = chooseDestinationFolder
            self.chooseMoveConflict = chooseMoveConflict
            self.requestRenameParameters = requestRenameParameters
        }
    }

    struct RecoveryAlertPresentation: Equatable {
        let folderURL: URL
        let title: String
        let message: String
        let details: String
    }

    struct PageControlAvailability: Equatable {
        let previous: Bool
        let next: Bool
    }

    private enum ContentRoute: Equatable {
        case viewer(URL)
        case folder(URL)
    }

    private struct FolderRouteState {
        let session: FolderSession?
        let isLoading: Bool
    }

    private let viewModel = ViewerViewModel()
    private let folderBrowserViewModel: FolderBrowserViewModel
    private let settings: AppSettings
    private let rootView = RootInteractionView()
    private let titleBarView = NSVisualEffectView()
    private let titleBarDivider = NSBox()
    private let titleLabel = NSTextField(labelWithString: "ImageView")
    private let titleBarGridButton = HoverToolbarButton()
    private let titleBarMoreButton = HoverToolbarButton()
    private let titleBarControlsStack = NSStackView()
    private lazy var titleBarDoubleClickRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(toggleWindowZoom(_:))
    )
    private let canvas = ImageCanvasView()
    private let continuousReadingView = ContinuousReadingView()
    private let folderBrowserView = FolderBrowserView()
    private let emptyStateView = EmptyStateView()
    private let errorStateView = ErrorStateView()
    private let cropOverlay = CropOverlayView()
    private let cropControlsView = NSHostingView(rootView: CropControlsView(onCancel: {}, onApply: {}))
    private let inspectorView = NSHostingView(rootView: InspectorView(metadata: nil))
    private let bottomBarView = NSVisualEffectView()
    private let bottomBarDivider = NSBox()
    private let bottomDimensionLabel = NSTextField(labelWithString: "— × — px")
    private let bottomPageLabel = NSTextField(labelWithString: "0 / 0")
    private let bottomZoomLabel = NSTextField(labelWithString: "100%")
    private lazy var bottomZoomClickRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(showZoomMenu(_:))
    )
    private let bottomInfoButton = NSButton()
    private let filmstripOverlayView = FilmstripOverlayView()
    private let filmstripView = FilmstripView()
    private let pageNavigationOverlayView = PageNavigationOverlayView()
    private let usageHintView = UsageHintView()
    private var cancellables: Set<AnyCancellable> = []
    private var gestureCoordinator: GestureCoordinator?
    private var keyMonitor: Any?
    private var displayedItemURL: URL?
    private var associatedViewerURL: URL?
    private var externalFileCheckTimer: Timer?
    private var filmstripHideTimer: Timer?
    private var filmstripVisibilityGeneration = 0
    private var isPointerOverFilmstrip = false
    private var pageControlsHideTimer: Timer?
    private var pageControlsVisibilityGeneration = 0
    private var usageHintTimer: Timer?
    private var canvasTrailingConstraint: NSLayoutConstraint!
    private var titleBarHeightConstraint: NSLayoutConstraint!
    private var bottomBarHeightConstraint: NSLayoutConstraint!
    private var isInspectorDocked = false
    private var isPointerOverPageControls = false
    private var folderRetryTask: Task<Void, Never>?
    private var continuousReadingTask: Task<Void, Never>?
    private var continuousReadingFocusID: ImageItem.ID?
    private var isInFullScreen = false
    private var fullScreenChromeHideTimer: Timer?
    private var lastAnnouncedLoadedURL: URL?
    private var folderRetryGeneration: UInt64 = 0
    private var isFolderBrowserMode = false
    private var currentFolderBrowserItems: [ImageItem] = []
    private var currentRoute: ContentRoute? {
        didSet { updateTitleBarControlAvailability() }
    }
    private var backRoute: ContentRoute? {
        didSet { updateTitleBarControlAvailability() }
    }
    private var forwardRoute: ContentRoute? {
        didSet { updateTitleBarControlAvailability() }
    }
    private var activeBatchRenameSheet: BatchRenameSheetController?
    var batchActionDialogProviderForTesting: BatchActionDialogProvider?
    var recoveryAlertPresenterForTesting: ((RecoveryAlertPresentation) -> Void)?
    var accessibilityAnnouncementHandlerForTesting: ((String) -> Void)?
    private var unsavedChangesChoiceForTesting: UnsavedChangesChoice?

    convenience init(
        settings: AppSettings = .shared,
        folderBrowserViewModel: FolderBrowserViewModel = FolderBrowserViewModel()
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ImageView"
        self.init(window: window, settings: settings, folderBrowserViewModel: folderBrowserViewModel)
        setup()
    }

    init(
        window: NSWindow?,
        settings: AppSettings = .shared,
        folderBrowserViewModel: FolderBrowserViewModel = FolderBrowserViewModel()
    ) {
        self.settings = settings
        self.folderBrowserViewModel = folderBrowserViewModel
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        folderRetryTask?.cancel()
        continuousReadingTask?.cancel()
        let folderBrowserViewModel = folderBrowserViewModel
        folderBrowserViewModel.invalidateOpenFolderRequest()
        Task { @MainActor in
            folderBrowserViewModel.cancelOpenFolderRequest()
        }
    }

    func open(url: URL) {
        hasAssignedOpenRequest = true
        confirmUnsavedEditsIfNeeded(for: .opening) { [weak self] in
            guard let self else { return }
            self.currentRoute = .viewer(url.standardizedFileURL)
            self.associatedViewerURL = nil
            self.backRoute = nil
            self.forwardRoute = nil
            self.openImageUsingExistingPipeline(url)
        }
    }

    private func openImageUsingExistingPipeline(_ url: URL) {
        exitFolderBrowserMode()
        cancelCrop(nil)
        Task { await viewModel.open(url: url) }
    }

    func openFolder(url: URL) {
        invalidateFolderRetry()
        hasAssignedOpenRequest = true
        currentRoute = .folder(url.standardizedFileURL)
        associatedViewerURL = nil
        backRoute = nil
        forwardRoute = nil
        enterFolderBrowserMode()
        Task { [weak self] in
            guard let self else { return }
            await self.folderBrowserViewModel.openFolder(url)
        }
    }

    private func setup() {
        window?.delegate = self
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.center()
        rootView.wantsLayer = true
        window?.acceptsMouseMovedEvents = true
        rootView.onFileDropped = { [weak self] url in
            self?.open(url: url)
        }
        emptyStateView.onOpenRequested = { [weak self] in
            self?.onOpenRequested?()
        }
        emptyStateView.onBrowseFolderRequested = { [weak self] in
            self?.onBrowseFolderRequested?()
        }
        emptyStateView.onOpenRecentRequested = { [weak self] url in
            self?.onOpenRecentRequested?(url)
        }
        emptyStateView.onClearRecentRequested = { [weak self] in
            self?.onClearRecentRequested?()
        }
        errorStateView.onRetryRequested = { [weak self] in
            self?.onOpenRequested?()
        }
        rootView.onPointerMoved = { [weak self] in
            guard let self else { return }
            self.hideUsageHint()
            self.revealFullScreenChromeIfNeeded()
            guard !self.isFolderBrowserMode else { return }
            self.revealFilmstripOverlay()
            self.revealPageControls()
        }
        filmstripOverlayView.onPointerEntered = { [weak self] in
            self?.isPointerOverFilmstrip = true
            self?.cancelFilmstripAutoHide()
        }
        filmstripOverlayView.onPointerExited = { [weak self] in
            self?.isPointerOverFilmstrip = false
            self?.scheduleFilmstripAutoHide()
        }
        pageNavigationOverlayView.onPrevious = { [weak self] in
            self?.navigateToPreviousImage()
        }
        pageNavigationOverlayView.onNext = { [weak self] in
            self?.navigateToNextImage()
        }
        pageNavigationOverlayView.onPointerEntered = { [weak self] in
            self?.isPointerOverPageControls = true
            self?.cancelPageControlsAutoHide()
        }
        pageNavigationOverlayView.onPointerExited = { [weak self] in
            self?.isPointerOverPageControls = false
            self?.schedulePageControlsAutoHide()
        }
        configureContentBars()
        canvas.autoresizingMask = [.width, .height]
        canvas.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = rootView
        rootView.addSubview(canvas)
        rootView.addSubview(continuousReadingView)
        rootView.addSubview(folderBrowserView)
        rootView.addSubview(emptyStateView)
        rootView.addSubview(errorStateView)
        rootView.addSubview(titleBarView)
        rootView.addSubview(titleBarDivider)
        rootView.addSubview(bottomBarView)
        rootView.addSubview(bottomBarDivider)
        rootView.addSubview(filmstripOverlayView)
        rootView.addSubview(pageNavigationOverlayView)
        rootView.addSubview(inspectorView)
        rootView.addSubview(usageHintView)
        bottomBarView.addSubview(bottomDimensionLabel)
        bottomBarView.addSubview(bottomPageLabel)
        bottomBarView.addSubview(bottomZoomLabel)
        bottomBarView.addSubview(bottomInfoButton)
        filmstripOverlayView.addSubview(filmstripView)
        rootView.addSubview(cropOverlay)
        rootView.addSubview(cropControlsView)
        folderBrowserView.translatesAutoresizingMaskIntoConstraints = false
        continuousReadingView.translatesAutoresizingMaskIntoConstraints = false
        continuousReadingView.isHidden = true
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        errorStateView.translatesAutoresizingMaskIntoConstraints = false
        inspectorView.translatesAutoresizingMaskIntoConstraints = false
        usageHintView.translatesAutoresizingMaskIntoConstraints = false
        usageHintView.isHidden = true
        usageHintView.onDismiss = { [weak self] in self?.hideUsageHint() }
        titleBarDivider.translatesAutoresizingMaskIntoConstraints = false
        bottomBarDivider.translatesAutoresizingMaskIntoConstraints = false
        for label in [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        bottomInfoButton.translatesAutoresizingMaskIntoConstraints = false
        filmstripOverlayView.translatesAutoresizingMaskIntoConstraints = false
        filmstripView.translatesAutoresizingMaskIntoConstraints = false
        pageNavigationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.translatesAutoresizingMaskIntoConstraints = false
        cropControlsView.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.isHidden = true
        cropControlsView.isHidden = true
        canvasTrailingConstraint = canvas.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
        titleBarHeightConstraint = titleBarView.heightAnchor.constraint(equalToConstant: Self.titleBarHeight)
        bottomBarHeightConstraint = bottomBarView.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight)
        NSLayoutConstraint.activate([
            titleBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            titleBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            titleBarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            titleBarHeightConstraint,
            titleBarDivider.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            titleBarDivider.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            titleBarDivider.bottomAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            titleBarDivider.heightAnchor.constraint(equalToConstant: 1),
            titleLabel.centerXAnchor.constraint(equalTo: titleBarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleBarControlsStack.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleBarView.trailingAnchor, constant: -72),
            titleBarControlsStack.leadingAnchor.constraint(equalTo: titleBarView.leadingAnchor, constant: 72),
            titleBarControlsStack.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            bottomBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            bottomBarHeightConstraint,
            bottomBarDivider.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            bottomBarDivider.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            bottomBarDivider.topAnchor.constraint(equalTo: bottomBarView.topAnchor),
            bottomBarDivider.heightAnchor.constraint(equalToConstant: 1),
            canvas.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            canvasTrailingConstraint,
            canvas.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
            continuousReadingView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            continuousReadingView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            continuousReadingView.topAnchor.constraint(equalTo: canvas.topAnchor),
            continuousReadingView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            folderBrowserView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            folderBrowserView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            folderBrowserView.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            folderBrowserView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
            emptyStateView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 24),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -24),
            errorStateView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            errorStateView.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            errorStateView.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 24),
            errorStateView.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -24),
            inspectorView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            inspectorView.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 16),
            inspectorView.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor, constant: -16),
            usageHintView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            usageHintView.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 18),
            usageHintView.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 20),
            usageHintView.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -20),
            bottomDimensionLabel.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 12),
            bottomDimensionLabel.trailingAnchor.constraint(lessThanOrEqualTo: bottomPageLabel.leadingAnchor, constant: -12),
            bottomDimensionLabel.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomPageLabel.centerXAnchor.constraint(equalTo: bottomBarView.centerXAnchor),
            bottomPageLabel.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomPageLabel.trailingAnchor.constraint(lessThanOrEqualTo: bottomZoomLabel.leadingAnchor, constant: -12),
            bottomZoomLabel.trailingAnchor.constraint(equalTo: bottomInfoButton.leadingAnchor, constant: -Self.bottomBarStatusToInfoSpacing),
            bottomZoomLabel.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomInfoButton.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -8),
            bottomInfoButton.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomInfoButton.widthAnchor.constraint(equalToConstant: 22),
            bottomInfoButton.heightAnchor.constraint(equalToConstant: 22),
            filmstripOverlayView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            filmstripOverlayView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -14),
            filmstripOverlayView.widthAnchor.constraint(equalTo: canvas.widthAnchor, multiplier: 0.72),
            filmstripOverlayView.heightAnchor.constraint(equalToConstant: Self.filmstripOverlayHeight),
            filmstripOverlayView.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 16),
            filmstripOverlayView.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -16),
            filmstripView.leadingAnchor.constraint(equalTo: filmstripOverlayView.leadingAnchor, constant: 10),
            filmstripView.trailingAnchor.constraint(equalTo: filmstripOverlayView.trailingAnchor, constant: -10),
            filmstripView.topAnchor.constraint(equalTo: filmstripOverlayView.topAnchor, constant: 10),
            filmstripView.bottomAnchor.constraint(equalTo: filmstripOverlayView.bottomAnchor, constant: -10),
            pageNavigationOverlayView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            pageNavigationOverlayView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            pageNavigationOverlayView.topAnchor.constraint(equalTo: canvas.topAnchor),
            pageNavigationOverlayView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            cropOverlay.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            cropOverlay.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            cropOverlay.topAnchor.constraint(equalTo: canvas.topAnchor),
            cropOverlay.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            cropControlsView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            cropControlsView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -24)
        ])

        canvas.onNext = { [weak self] in self?.navigateToNextImage() }
        canvas.onPrevious = { [weak self] in self?.navigateToPreviousImage() }
        continuousReadingView.onFocusedItemChanged = { [weak self] itemID in
            guard let self else { return }
            self.continuousReadingFocusID = itemID
            self.refreshContinuousReadingWindow()
        }
        canvas.onTransformChanged = { [weak self] scale in
            guard let self else { return }
            self.updateZoomStatus()
            if scale > 1.01 {
                self.hideFilmstripOverlay(immediately: true)
            }
        }
        gestureCoordinator = GestureCoordinator(canvas: canvas)
        filmstripView.onSelect = { [weak self] item in
            self?.selectImage(item)
        }
        folderBrowserView.onOpenItem = { [weak self] item in
            self?.openFolderBrowserItem(item)
        }
        folderBrowserView.onSelectionChanged = { [weak self] selectedIDs in
            self?.folderBrowserViewModel.setSelection(Array(selectedIDs))
        }
        folderBrowserView.onSearchChanged = { [weak self] searchText in
            self?.folderBrowserViewModel.searchText = searchText
        }
        folderBrowserView.onSortChanged = { [weak self] sortMode in
            self?.folderBrowserViewModel.setSortMode(sortMode)
        }
        folderBrowserView.onTypeFilterChanged = { [weak self] formats in
            self?.folderBrowserViewModel.setAllowedFormats(formats)
        }
        folderBrowserView.onClearFilters = { [weak self] in
            self?.folderBrowserViewModel.clearFilters()
        }
        folderBrowserView.onRetryFolder = { [weak self] in
            self?.startFolderRetry()
        }
        folderBrowserView.onChooseAnotherFolder = { [weak self] in
            self?.onBrowseFolderRequested?()
        }
        folderBrowserView.onMoveToTrash = { [weak self] in
            self?.moveSelectedFolderBrowserItemsToTrash()
        }
        folderBrowserView.onMoveToFolder = { [weak self] in
            self?.moveSelectedFolderBrowserItemsToFolder()
        }
        folderBrowserView.onBatchRename = { [weak self] in
            self?.renameSelectedFolderBrowserItems()
        }
        folderBrowserView.onCancelOperation = { [weak self] in
            self?.folderBrowserViewModel.cancelCurrentOperation()
        }
        folderBrowserView.onUndoLastOperation = { [weak self] in
            self?.folderBrowserViewModel.undoLastBatchOperation()
        }
        folderBrowserView.onShowOperationDetails = { [weak self] details in
            self?.presentBatchOperationDetails(details)
        }
        folderBrowserViewModel.onItemURLMutation = { [weak self] mutation in
            self?.applyFolderItemURLMutation(mutation)
        }
        folderBrowserViewModel.onRecoveryRequired = { [weak self] folderURL, failures in
            self?.presentRecoveryRequiredAlert(folderURL: folderURL, failures: failures)
        }

        viewModel.$currentImage
            .sink { [weak self] image in
                guard let self else { return }
                self.canvas.image = image
                self.updateContinuousReadingPresentation()
                if image == nil {
                    self.hideFilmstripOverlay(immediately: true)
                }
                guard self.settings.animatesNavigationTransitions,
                      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      image != nil else { return }
                self.canvas.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    self.canvas.animator().alphaValue = 1
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            folderBrowserViewModel.$session,
            folderBrowserViewModel.$isLoading,
            folderBrowserViewModel.$loadErrorMessage
        )
            .sink { [weak self] session, isLoading, loadErrorMessage in
                guard let self else { return }
                let items = session?.visibleItems ?? []
                if self.currentFolderBrowserItems != items {
                    self.currentFolderBrowserItems = items
                    self.folderBrowserView.applyItems(items)
                }
                self.folderBrowserView.applyFilter(session?.filter ?? FolderFilter())
                self.folderBrowserView.applyCounts(
                    total: session?.items.count ?? 0,
                    visible: session?.visibleItems.count ?? 0,
                    selected: self.folderBrowserViewModel.selectedItemIDs.count
                )
                self.folderBrowserView.applyPresentation(Self.folderBrowserPresentation(
                    session: session,
                    isLoading: isLoading,
                    loadErrorMessage: loadErrorMessage
                ))
                self.updateTitleBarControlAvailability(
                    folderState: FolderRouteState(session: session, isLoading: isLoading)
                )
                self.updateWindowTitle(viewerTitle: self.viewModel.displayTitle)
            }
            .store(in: &cancellables)

        folderBrowserViewModel.$selectedItemIDs
            .removeDuplicates()
            .sink { [weak self] selectedItemIDs in
                guard let self else { return }
                self.folderBrowserView.applySelection(Set(selectedItemIDs))
                self.folderBrowserView.applyCounts(
                    total: self.folderBrowserViewModel.session?.items.count ?? 0,
                    visible: self.folderBrowserViewModel.session?.visibleItems.count ?? 0,
                    selected: selectedItemIDs.count
                )
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            folderBrowserViewModel.$operationMessage,
            folderBrowserViewModel.$operationFailures,
            folderBrowserViewModel.$operationRecoveryFailures,
            folderBrowserViewModel.$isOperating
        )
            .sink { [weak self] message, failures, recoveryFailures, isOperating in
                self?.folderBrowserView.applyOperationStatus(
                    message: message,
                    failures: failures,
                    recoveryFailures: recoveryFailures,
                    isOperating: isOperating
                )
            }
            .store(in: &cancellables)

        folderBrowserViewModel.$operationProgress
            .sink { [weak self] progress in
                self?.folderBrowserView.applyProgress(progress)
            }
            .store(in: &cancellables)

        folderBrowserViewModel.$canUndoLastBatchOperation
            .sink { [weak self] isAvailable in
                self?.folderBrowserView.applyUndoAvailability(isAvailable)
            }
            .store(in: &cancellables)

        viewModel.$displayTitle
            .sink { [weak self] title in
                self?.updateWindowTitle(viewerTitle: title)
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .sink { [weak self] message in
                self?.errorStateView.message = message ?? ""
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            viewModel.$currentImage,
            viewModel.$loadPhase,
            viewModel.$errorMessage
        )
            .sink { [weak self] image, loadPhase, errorMessage in
                guard let self else { return }
                self.updateEmptyStatePresentation(
                    hasCurrentImage: image != nil,
                    loadPhase: loadPhase,
                    hasError: errorMessage != nil
                )
                self.announceLoadedImageIfNeeded(hasImage: image != nil, loadPhase: loadPhase)
            }
            .store(in: &cancellables)

        viewModel.$currentMetadata
            .sink { [weak self] metadata in
                guard let self else { return }
                self.updateInspector(metadata: metadata)
                self.updateDimensionStatus(metadata: metadata)
            }
            .store(in: &cancellables)

        viewModel.$navigationState
            .sink { [weak self] state in
                guard let self else { return }
                self.continuousReadingFocusID = state?.currentItem?.id
                let newURL = state?.currentItem?.url
                let didNavigate = self.displayedItemURL != nil
                    && Self.shouldResetCanvasTransform(from: self.displayedItemURL, to: newURL)
                if Self.shouldResetCanvasTransform(from: self.displayedItemURL, to: newURL) {
                    self.canvas.resetViewTransform()
                }
                self.displayedItemURL = newURL?.standardizedFileURL
                if case .viewer = self.currentRoute, let newURL {
                    self.currentRoute = .viewer(newURL.standardizedFileURL)
                    if self.associatedViewerURL != nil {
                        self.associatedViewerURL = newURL.standardizedFileURL
                    }
                }
                self.filmstripView.apply(items: state?.items ?? [], current: state?.currentItem)
                let availability = Self.pageControlAvailability(
                    navigationState: state,
                    readingDirection: self.settings.readingDirection
                )
                self.pageNavigationOverlayView.update(
                    previousEnabled: availability.previous,
                    nextEnabled: availability.next
                )
                if Self.shouldDisplayPageControls(
                    itemCount: state?.items.count ?? 0,
                    isCropping: self.cropOverlay.isCropping
                ) {
                    if didNavigate {
                        self.revealPageControls()
                    }
                } else {
                    self.hidePageControls(immediately: true)
                }
                self.updatePageStatus(navigationState: state)
                self.updateTitleBarControlAvailability()
                self.updateContinuousReadingPresentation()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.applySettings()
                }
            }
            .store(in: &cancellables)

        installKeyMonitor()
        applySettings()
        updateDimensionStatus(metadata: viewModel.currentMetadata)
        updatePageStatus(navigationState: viewModel.navigationState)
        let availability = Self.pageControlAvailability(
            navigationState: viewModel.navigationState,
            readingDirection: settings.readingDirection
        )
        pageNavigationOverlayView.update(
            previousEnabled: availability.previous,
            nextEnabled: availability.next
        )
        updateZoomStatus()
    }

    override func keyDown(with event: NSEvent) {
        guard !handleKeyDown(event) else { return }
        super.keyDown(with: event)
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        guard gestureRecognizer === titleBarDoubleClickRecognizer else { return true }
        let location = titleBarView.convert(event.locationInWindow, from: nil)
        return shouldRecognizeTitleBarDoubleClick(hitView: titleBarView.hitTest(location))
    }

    @objc func renameCurrentImage(_ sender: Any?) {
        cancelCrop(nil)
        guard let item = viewModel.navigationState?.currentItem else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = "重命名"
        alert.informativeText = "输入新的文件名（不含扩展名）。"
        let textField = NSTextField(string: item.url.deletingPathExtension().lastPathComponent)
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = textField
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = textField.stringValue
        confirmUnsavedEditsIfNeeded(for: .renaming) { [weak self] in
            self?.viewModel.renameCurrent(to: newName)
        }
    }

    @objc func revealCurrentImageInFinder(_ sender: Any?) {
        viewModel.revealCurrentInFinder()
    }

    @objc func toggleWindowZoom(_ sender: Any?) {
        window?.zoom(sender)
    }

    @objc func copyCurrentImagePath(_ sender: Any?) {
        viewModel.copyCurrentPathToPasteboard()
    }

    @objc func moveCurrentImageToTrash(_ sender: Any?) {
        cancelCrop(nil)
        guard confirmMoveCurrentImageToTrash() else { return }
        confirmUnsavedEditsIfNeeded(for: .movingToTrash) { [weak self] in
            self?.viewModel.moveCurrentToTrash()
        }
    }

    @objc func rotateClockwise(_ sender: Any?) {
        performEdit(.rotateClockwise)
    }

    @objc func rotateCounterClockwise(_ sender: Any?) {
        performEdit(.rotateCounterClockwise)
    }

    @objc func mirrorHorizontal(_ sender: Any?) {
        performEdit(.mirrorHorizontal)
    }

    @objc func mirrorVertical(_ sender: Any?) {
        performEdit(.mirrorVertical)
    }

    @objc func startCropping(_ sender: Any?) {
        guard viewModel.canEditCurrentImage,
              let imageDrawRect = canvas.imageDrawRect else {
            NSSound.beep()
            return
        }

        cropOverlay.beginCropping(in: imageDrawRect)
        updateCropControls()
        window?.makeFirstResponder(cropOverlay)
    }

    @objc func applyCrop(_ sender: Any?) {
        guard viewModel.canEditCurrentImage,
              cropOverlay.isCropping,
              let pixelCropRect = canvas.pixelCropRect(for: cropOverlay.cropRect) else {
            NSSound.beep()
            return
        }

        performEdit(.crop(pixelCropRect))
        cancelCrop(nil)
    }

    @objc func cancelCrop(_ sender: Any?) {
        cropOverlay.endCropping()
        updateCropControls()
        window?.makeFirstResponder(canvas)
    }

    @objc func saveEdits(_ sender: Any?) {
        guard viewModel.canEditCurrentImage else {
            NSSound.beep()
            return
        }
        _ = viewModel.saveCurrentEdits()
    }

    @objc func saveEditsAs(_ sender: Any?) {
        guard viewModel.canEditCurrentImage, viewModel.hasUnsavedEdits else {
            NSSound.beep()
            return
        }

        let formats = ImageEditingService.writableSaveFormats()
        let panel = NSSavePanel()
        panel.allowedContentTypes = formats.compactMap(\.contentType)
        let baseName = URL(fileURLWithPath: viewModel.currentFilename).deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName)-edited.png"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
            return
        }
        _ = viewModel.saveCurrentEdits(to: url, format: format)
    }

    @objc func discardEdits(_ sender: Any?) {
        guard viewModel.currentImage != nil else {
            NSSound.beep()
            return
        }
        _ = viewModel.discardCurrentEdits()
    }

    @objc func undoEdit(_ sender: Any?) {
        if !viewModel.undoEdit() { NSSound.beep() }
    }

    @objc func redoEdit(_ sender: Any?) {
        if !viewModel.redoEdit() { NSSound.beep() }
    }

    @objc func toggleFilmstrip(_ sender: Any?) {
        settings.showsFilmstrip.toggle()
        if settings.showsFilmstrip {
            revealFilmstripOverlay()
        } else {
            hideFilmstripOverlay(immediately: true)
        }
    }

    @objc func toggleInspector(_ sender: Any?) {
        settings.showsInspector.toggle()
    }

    @objc func toggleContinuousReading(_ sender: Any?) {
        settings.usesContinuousReading.toggle()
    }

    @objc func showPreviousImage(_ sender: Any?) {
        navigateToPreviousImage()
    }

    @objc func showNextImage(_ sender: Any?) {
        navigateToNextImage()
    }

    @objc func actualSize(_ sender: Any?) {
        canvas.zoomToActualSize()
    }

    @objc func zoomToFit(_ sender: Any?) {
        canvas.resetViewTransform()
    }

    @objc func zoomToFitWidth(_ sender: Any?) {
        canvas.zoomToFitWidth()
    }

    @objc private func setZoomPercentage(_ sender: NSMenuItem) {
        canvas.setManualPercentage(CGFloat(sender.tag))
    }

    @objc private func setCustomZoomPercentage(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("viewer.zoom.custom.title")
        alert.informativeText = AppStrings.text("viewer.zoom.custom.message")
        let currentPercentage = Int(((canvas.pixelScale ?? 1) * 100).rounded())
        let field = NSTextField(string: "\(currentPercentage)")
        field.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        field.setAccessibilityLabel(AppStrings.text("viewer.zoom.custom.field"))
        alert.accessoryView = field
        alert.addButton(withTitle: AppStrings.text("viewer.zoom.custom.apply"))
        alert.addButton(withTitle: AppStrings.text("viewer.zoom.custom.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn,
              let percentage = Double(field.stringValue),
              percentage.isFinite,
              percentage >= 10,
              percentage <= 1_200 else {
            return
        }
        canvas.setManualPercentage(CGFloat(percentage))
    }

    @objc private func showZoomMenu(_ sender: Any?) {
        let menu = NSMenu()
        let fitItem = NSMenuItem(
            title: AppStrings.text("menu.view.zoomToFit"),
            action: #selector(zoomToFit(_:)),
            keyEquivalent: ""
        )
        fitItem.target = self
        fitItem.state = canvas.displayMode == .fit ? .on : .off
        menu.addItem(fitItem)
        let fitWidthItem = NSMenuItem(
            title: AppStrings.text("menu.view.zoomToFitWidth"),
            action: #selector(zoomToFitWidth(_:)),
            keyEquivalent: ""
        )
        fitWidthItem.target = self
        fitWidthItem.state = canvas.displayMode == .fitWidth ? .on : .off
        menu.addItem(fitWidthItem)
        menu.addItem(.separator())

        for percentage in [50, 100, 200] {
            let item = NSMenuItem(
                title: "\(percentage)%",
                action: #selector(setZoomPercentage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = percentage
            if canvas.displayMode == .manual,
               let pixelScale = canvas.pixelScale,
               abs(pixelScale * 100 - CGFloat(percentage)) < 0.5 {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let customItem = NSMenuItem(
            title: AppStrings.text("viewer.zoom.custom.menu"),
            action: #selector(setCustomZoomPercentage(_:)),
            keyEquivalent: ""
        )
        customItem.target = self
        menu.addItem(customItem)

        let location = NSPoint(x: bottomZoomLabel.bounds.minX, y: bottomZoomLabel.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: location, in: bottomZoomLabel)
    }

    @objc func browseCurrentImageFolder(_ sender: Any?) {
        if case .folder = currentRoute {
            guard let viewerRoute = associatedViewerRoute() else {
                NSSound.beep()
                return
            }
            showRoute(viewerRoute, recordHistory: false)
            return
        }

        guard let viewerURL = currentViewerURL else {
            NSSound.beep()
            return
        }
        let folderURL = viewerURL.deletingLastPathComponent().standardizedFileURL
        associatedViewerURL = viewerURL.standardizedFileURL
        if folderBrowserViewModel.session?.folderURL.standardizedFileURL == folderURL {
            showRoute(.folder(folderURL), recordHistory: false)
            return
        }

        currentRoute = .folder(folderURL)
        enterFolderBrowserMode()
        invalidateFolderRetry()
        Task { [weak self] in
            guard let self else { return }
            await self.folderBrowserViewModel.openFolder(folderURL)
        }
    }

    private var currentViewerURL: URL? {
        if case let .viewer(url) = currentRoute {
            return url
        }
        return displayedItemURL
    }

    private func associatedViewerRoute(folderState: FolderRouteState? = nil) -> ContentRoute? {
        if let associatedViewerURL {
            return .viewer(associatedViewerURL)
        }
        let folderState = folderState ?? FolderRouteState(
            session: folderBrowserViewModel.session,
            isLoading: folderBrowserViewModel.isLoading
        )
        let matchingLoadedSession: FolderSession?
        if case let .folder(folderURL) = currentRoute,
           !folderState.isLoading,
           let session = folderState.session,
           session.folderURL.standardizedFileURL == folderURL.standardizedFileURL {
            matchingLoadedSession = session
        } else {
            matchingLoadedSession = nil
        }

        if let displayedItemURL {
            let displayedURL = displayedItemURL.standardizedFileURL
            if matchingLoadedSession == nil || matchingLoadedSession?.items.contains(where: {
                $0.url.standardizedFileURL == displayedURL
            }) == true {
                return .viewer(displayedURL)
            }
        }
        if let lastOpenedItemID = matchingLoadedSession?.lastOpenedItemID,
           let item = matchingLoadedSession?.items.first(where: { $0.id == lastOpenedItemID }) {
            return .viewer(item.url.standardizedFileURL)
        }
        if case let .viewer(url)? = backRoute ?? forwardRoute {
            return .viewer(url)
        }
        return nil
    }

    private func openFolderBrowserItem(_ item: ImageItem) {
        confirmUnsavedEditsIfNeeded(for: .opening) { [weak self] in
            guard let self else { return }
            self.folderBrowserViewModel.recordOpenedItem(item)
            self.associatedViewerURL = item.url.standardizedFileURL
            self.showRoute(.viewer(item.url.standardizedFileURL), recordHistory: true)
            self.hasAssignedOpenRequest = true
            self.openImageUsingExistingPipeline(item.url)
        }
    }

    private func applyFolderItemURLMutation(_ mutation: FolderItemURLMutation) {
        switch mutation {
        case let .removed(urls):
            let standardizedURLs = Set(urls.map(\.standardizedFileURL))
            let currentViewerWasRemoved: Bool
            if case let .viewer(url) = currentRoute {
                currentViewerWasRemoved = standardizedURLs.contains(url.standardizedFileURL)
            } else {
                currentViewerWasRemoved = false
            }
            backRoute = removingViewerRoute(backRoute, matchingAny: standardizedURLs)
            forwardRoute = removingViewerRoute(forwardRoute, matchingAny: standardizedURLs)
            if let associatedViewerURL,
               standardizedURLs.contains(associatedViewerURL.standardizedFileURL) {
                self.associatedViewerURL = nil
            }
            let replacementURL = viewModel.removeItemsFromNavigation(standardizedURLs)
            if currentViewerWasRemoved {
                currentRoute = replacementURL.map(ContentRoute.viewer)
            }
        case let .renamed(migrations):
            let standardizedMigrations = Dictionary(
                uniqueKeysWithValues: migrations.map {
                    ($0.key.standardizedFileURL, $0.value.standardizedFileURL)
                }
            )
            currentRoute = migratingViewerRoute(currentRoute, using: standardizedMigrations)
            backRoute = migratingViewerRoute(backRoute, using: standardizedMigrations)
            forwardRoute = migratingViewerRoute(forwardRoute, using: standardizedMigrations)
            if let associatedViewerURL,
               let destination = standardizedMigrations[associatedViewerURL.standardizedFileURL] {
                self.associatedViewerURL = destination
            }
            viewModel.applyItemURLMigrations(standardizedMigrations)
        }
    }

    private func presentRecoveryRequiredAlert(folderURL: URL, failures: [BatchRecoveryFailure]) {
        let presentation = Self.recoveryAlertPresentation(folderURL: folderURL, failures: failures)
        if let recoveryAlertPresenterForTesting {
            recoveryAlertPresenterForTesting(presentation)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = presentation.title
        alert.informativeText = presentation.message
        alert.addButton(withTitle: AppStrings.text("common.ok"))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = presentation.details
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentBatchOperationDetails(_ details: String) {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("folderBrowser.operation.detailsTitle")
        alert.addButton(withTitle: AppStrings.text("common.ok"))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = details
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static func recoveryAlertPresentation(
        folderURL: URL,
        failures: [BatchRecoveryFailure]
    ) -> RecoveryAlertPresentation {
        let detailLines = failures.flatMap { failure -> [String] in
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
        return RecoveryAlertPresentation(
            folderURL: folderURL,
            title: AppStrings.text("folderBrowser.recovery.alert.title"),
            message: String(
                format: AppStrings.text("folderBrowser.recovery.alert.folder"),
                folderURL.path
            ),
            details: detailLines.joined(separator: "\n")
        )
    }

    private func migratingViewerRoute(_ route: ContentRoute?, using migrations: [URL: URL]) -> ContentRoute? {
        guard case let .viewer(url) = route,
              let destination = migrations[url.standardizedFileURL] else {
            return route
        }
        return .viewer(destination)
    }

    private func removingViewerRoute(_ route: ContentRoute?, matchingAny removedURLs: Set<URL>) -> ContentRoute? {
        guard case let .viewer(url) = route,
              removedURLs.contains(url.standardizedFileURL) else {
            return route
        }
        return nil
    }

    private func showRoute(_ route: ContentRoute, recordHistory: Bool) {
        if recordHistory, currentRoute != route {
            backRoute = currentRoute
            forwardRoute = nil
        }
        currentRoute = route
        switch route {
        case .viewer:
            exitFolderBrowserMode()
        case .folder:
            enterFolderBrowserMode()
        }
    }

    private func goBack() {
        guard let target = backRoute, target != currentRoute else { return }
        let previousRoute = currentRoute
        backRoute = nil
        forwardRoute = previousRoute
        showRoute(target, recordHistory: false)
    }

    private func goForward() {
        guard let target = forwardRoute, target != currentRoute else { return }
        let previousRoute = currentRoute
        forwardRoute = nil
        backRoute = previousRoute
        showRoute(target, recordHistory: false)
    }

    private func moveSelectedFolderBrowserItemsToTrash() {
        let selectedItems = folderBrowserViewModel.selectedItems
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        let confirmed = batchActionDialogProviderForTesting?.confirmTrash?(selectedItems.count)
            ?? confirmMoveSelectedFolderBrowserItemsToTrash(count: selectedItems.count)
        guard confirmed else { return }

        confirmUnsavedEditsForSelectedViewerIfNeeded(selectedItems, transition: .movingToTrash) { [weak self] in
            self?.folderBrowserViewModel.moveSelectedToTrash()
        }
    }

    private func moveSelectedFolderBrowserItemsToFolder() {
        let selectedItems = folderBrowserViewModel.selectedItems
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        let destination = batchActionDialogProviderForTesting?.chooseDestinationFolder?()
            ?? chooseDestinationFolderForBatchMove()
        guard let destination else { return }

        guard let skipPlan = folderBrowserViewModel.planSelectedMove(
            to: destination,
            conflictPolicy: .skip
        ) else { return }

        let choice: MoveConflictChoice
        if skipPlan.conflictingNames.isEmpty {
            choice = .skipConflicts
        } else {
            choice = batchActionDialogProviderForTesting?.chooseMoveConflict?(skipPlan.conflictingNames)
                ?? chooseMoveConflict(names: skipPlan.conflictingNames)
        }
        guard choice != .cancel else { return }

        confirmUnsavedEditsForSelectedViewerIfNeeded(selectedItems, transition: .navigating) { [weak self] in
            guard let self else { return }
            switch choice {
            case .skipConflicts:
                self.folderBrowserViewModel.executeMovePlan(skipPlan)
            case .keepBoth:
                guard let keepBothPlan = self.folderBrowserViewModel.planSelectedMove(
                    to: destination,
                    conflictPolicy: .keepBoth
                ) else { return }
                self.folderBrowserViewModel.executeMovePlan(keepBothPlan)
            case .cancel:
                break
            }
        }
    }

    private func confirmUnsavedEditsForSelectedViewerIfNeeded(
        _ selectedItems: [ImageItem],
        transition: UnsavedChangesTransition,
        perform action: () -> Void
    ) {
        let selectedURLs = Set(selectedItems.map { $0.url.standardizedFileURL })
        guard let viewerURL = viewModel.navigationState?.currentItem?.url.standardizedFileURL,
              selectedURLs.contains(viewerURL) else {
            action()
            return
        }
        confirmUnsavedEditsIfNeeded(for: transition, perform: action)
    }

    private func renameSelectedFolderBrowserItems() {
        let selectedItems = folderBrowserViewModel.selectedItems
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        let folderBrowserViewModel = self.folderBrowserViewModel
        let planRename: BatchRenameSheetController.PlanRename = { urls, baseName, startNumber, padding in
            folderBrowserViewModel.planBatchRename(
                urls: urls,
                baseName: baseName,
                startNumber: startNumber,
                padding: padding
            )
        }
        let confirm: (BatchRenameSheetController.RenameParameters, BatchRenamePlan) -> Void = { [weak self] _, plan in
            guard let self else { return }
            self.confirmUnsavedEditsForSelectedViewerIfNeeded(selectedItems, transition: .renaming) {
                self.folderBrowserViewModel.executeRenamePlan(plan)
            }
        }

        if let requestRenameParameters = batchActionDialogProviderForTesting?.requestRenameParameters {
            requestRenameParameters(selectedItems, planRename, confirm)
        } else {
            showBatchRenameSheet(items: selectedItems, planRename: planRename, onConfirm: confirm)
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else {
                return event
            }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        hideUsageHint()
        revealFullScreenChromeIfNeeded()
        switch Self.keyAction(
            for: event.keyCode,
            shouldEndEditing: shouldEndEditing(for: event),
            isCropping: cropOverlay.isCropping,
            modifierFlags: event.modifierFlags,
            isFolderBrowserMode: isFolderBrowserMode
        ) {
        case .showPrevious:
            navigateToPreviousImage()
            return true
        case .showNext:
            navigateToNextImage()
            return true
        case .closeWindow:
            window?.performClose(nil)
            return true
        case .moveToTrash:
            guard confirmMoveCurrentImageToTrash() else { return true }
            confirmUnsavedEditsIfNeeded(for: .movingToTrash) { [weak self] in
                self?.viewModel.moveCurrentToTrash()
            }
            return true
        case .toggleZoom:
            canvas.toggleFitOrActualSize()
            return true
        case .toggleFullscreen:
            window?.toggleFullScreen(nil)
            return true
        case .startCropping:
            startCropping(nil)
            return true
        case .applyCrop:
            applyCrop(nil)
            return true
        case .cancelCrop:
            cancelCrop(nil)
            return true
        case .endEditing:
            window?.endEditing(for: nil)
            return true
        case .passThrough:
            return false
        }
    }

    private func shouldEndEditing(for event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              let window,
              let responder = window.firstResponder else {
            return false
        }

        return responder is NSText || responder is NSTextView
    }

    static func keyAction(
        for keyCode: UInt16,
        shouldEndEditing: Bool,
        isCropping: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = [],
        isFolderBrowserMode: Bool = false
    ) -> KeyAction {
        if keyCode == 13, modifierFlags.contains(.command) {
            return .closeWindow
        }

        if isFolderBrowserMode {
            switch keyCode {
            case 53:
                return shouldEndEditing ? .endEditing : .passThrough
            default:
                return .passThrough
            }
        }

        if isCropping {
            switch keyCode {
            case 36:
                return .applyCrop
            case 53:
                return .cancelCrop
            default:
                break
            }
        }

        switch keyCode {
        case 123:
            return .showPrevious
        case 124:
            return .showNext
        case 51:
            return .moveToTrash
        case 49:
            return .toggleZoom
        case 40 where modifierFlags.contains(.command):
            return .startCropping
        case 36:
            return .toggleFullscreen
        case 53:
            return shouldEndEditing ? .endEditing : .passThrough
        default:
            return .passThrough
        }
    }

    static func shouldRefreshCurrentFileOnWindowActivation() -> Bool {
        true
    }

    static func shouldResetCanvasTransform(from previousURL: URL?, to newURL: URL?) -> Bool {
        previousURL?.standardizedFileURL != newURL?.standardizedFileURL
    }

    static func resolveUnsavedChanges(choice: UnsavedChangesChoice, saveSucceeded: Bool) -> UnsavedChangesResolution {
        switch choice {
        case .save:
            return saveSucceeded ? .proceed : .stayOnCurrentImage
        case .discard:
            return .proceed
        case .cancel:
            return .stayOnCurrentImage
        }
    }

    static func menuCommand(for action: Selector?) -> MenuCommand? {
        switch action {
        case #selector(renameCurrentImage(_:)),
             #selector(revealCurrentImageInFinder(_:)),
             #selector(copyCurrentImagePath(_:)),
             #selector(moveCurrentImageToTrash(_:)):
            return .fileOperationRequiringCurrentItem
        case #selector(showPreviousImage(_:)), #selector(showNextImage(_:)):
            return .navigation
        case #selector(actualSize(_:)), #selector(zoomToFit(_:)), #selector(zoomToFitWidth(_:)):
            return .canvasSizing
        case #selector(startCropping(_:)):
            return .startCropping
        case #selector(rotateClockwise(_:)):
            return .editOperation(.rotateClockwise)
        case #selector(rotateCounterClockwise(_:)):
            return .editOperation(.rotateCounterClockwise)
        case #selector(mirrorHorizontal(_:)):
            return .editOperation(.mirrorHorizontal)
        case #selector(mirrorVertical(_:)):
            return .editOperation(.mirrorVertical)
        case #selector(saveEdits(_:)):
            return .saveEdits
        case #selector(saveEditsAs(_:)):
            return .saveEditsAs
        case #selector(discardEdits(_:)):
            return .discardEdits
        case #selector(undoEdit(_:)):
            return .undoEdit
        case #selector(redoEdit(_:)):
            return .redoEdit
        default:
            return nil
        }
    }

    static func isMenuCommandEnabled(
        _ command: MenuCommand,
        hasCurrentItem: Bool,
        hasCurrentImage: Bool,
        canEditCurrentImage: Bool,
        hasUnsavedEdits: Bool,
        isFolderBrowserMode: Bool = false
    ) -> Bool {
        if isFolderBrowserMode {
            return false
        }

        switch command {
        case .fileOperationRequiringCurrentItem:
            return hasCurrentItem
        case .navigation:
            return hasCurrentItem
        case .canvasSizing:
            return hasCurrentImage
        case .startCropping:
            return canEditCurrentImage
        case .editOperation:
            return canEditCurrentImage
        case .saveEdits, .saveEditsAs:
            return canEditCurrentImage && hasUnsavedEdits
        case .discardEdits:
            return hasCurrentImage && hasUnsavedEdits
        case .undoEdit:
            return hasCurrentImage && hasUnsavedEdits
        case .redoEdit:
            return hasCurrentImage
        }
    }

    private func updateDimensionStatus(metadata: ImageMetadata?) {
        bottomDimensionLabel.stringValue = Self.dimensionText(
            pixelWidth: metadata?.pixelWidth,
            pixelHeight: metadata?.pixelHeight
        )
    }

    private func updatePageStatus(navigationState: NavigationState?) {
        bottomPageLabel.stringValue = Self.pageText(navigationState: navigationState)
    }

    private func updateZoomStatus() {
        bottomZoomLabel.stringValue = Self.zoomText(
            displayMode: canvas.displayMode,
            pixelScale: canvas.pixelScale
        )
        bottomZoomLabel.setAccessibilityValue(bottomZoomLabel.stringValue)
    }

    private func updateCropControls() {
        cropControlsView.rootView = CropControlsView(
            onCancel: { [weak self] in self?.cancelCrop(nil) },
            onApply: { [weak self] in self?.applyCrop(nil) }
        )
        cropControlsView.isHidden = !cropOverlay.isCropping
        if cropOverlay.isCropping {
            hidePageControls(immediately: true)
        }
    }

    private func confirmMoveCurrentImageToTrash() -> Bool {
        guard let item = viewModel.navigationState?.currentItem else {
            NSSound.beep()
            return false
        }
        guard settings.confirmsDelete else { return true }

        let alert = NSAlert()
        alert.messageText = AppStrings.text("viewer.confirmTrash.title")
        alert.informativeText = String(
            format: AppStrings.text("viewer.confirmTrash.message"),
            item.url.lastPathComponent
        )
        alert.addButton(withTitle: AppStrings.text("viewer.confirmTrash.button"))
        alert.addButton(withTitle: AppStrings.text("viewer.confirmTrash.cancel"))

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmMoveSelectedFolderBrowserItemsToTrash(count: Int) -> Bool {
        guard settings.confirmsDelete else { return true }

        let alert = NSAlert()
        alert.messageText = String(format: AppStrings.text("folderBrowser.confirmTrash.title"), count)
        alert.informativeText = AppStrings.text("folderBrowser.confirmTrash.message")
        alert.addButton(withTitle: AppStrings.text("folderBrowser.confirmTrash.button"))
        alert.addButton(withTitle: AppStrings.text("folderBrowser.confirmTrash.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func chooseDestinationFolderForBatchMove() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = AppStrings.text("folderBrowser.movePanel.prompt")
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseMoveConflict(names: [String]) -> MoveConflictChoice {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("folderBrowser.moveConflict.title")
        alert.informativeText = AppStrings.text("folderBrowser.moveConflict.message")
        alert.addButton(withTitle: AppStrings.text("folderBrowser.moveConflict.skip"))
        alert.addButton(withTitle: AppStrings.text("folderBrowser.moveConflict.keepBoth"))
        alert.addButton(withTitle: AppStrings.text("folderBrowser.moveConflict.cancel"))

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.string = names.joined(separator: "\n")

        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .skipConflicts
        case .alertSecondButtonReturn:
            return .keepBoth
        default:
            return .cancel
        }
    }

    private func showBatchRenameSheet(
        items: [ImageItem],
        planRename: @escaping BatchRenameSheetController.PlanRename,
        onConfirm: @escaping (BatchRenameSheetController.RenameParameters, BatchRenamePlan) -> Void
    ) {
        let controller = BatchRenameSheetController(items: items, planRename: planRename)
        controller.onConfirm = { [weak self] parameters, plan in
            onConfirm(parameters, plan)
            self?.activeBatchRenameSheet = nil
        }

        guard controller.window != nil, let window else {
            return
        }
        activeBatchRenameSheet = controller
        controller.beginSheet(on: window) { [weak self] _ in
            self?.activeBatchRenameSheet = nil
        }
    }

    private func applySettings() {
        canvas.backgroundColor = Self.canvasBackgroundColor()
        if !settings.showsFilmstrip {
            hideFilmstripOverlay(immediately: true)
        }
        inspectorView.isHidden = !Self.shouldDisplayInspector(
            isEnabled: settings.showsInspector,
            hasCurrentImage: viewModel.currentImage != nil
        )
        updateInspectorLayout()
        bottomInfoButton.state = settings.showsInspector ? .on : .off
        updateDimensionStatus(metadata: viewModel.currentMetadata)
        updatePageStatus(navigationState: viewModel.navigationState)
        updateZoomStatus()
        updateContinuousReadingPresentation()
    }

    private func updateContinuousReadingPresentation() {
        let shouldShow = settings.usesContinuousReading
            && viewModel.currentImage != nil
            && !isFolderBrowserMode
        continuousReadingView.isHidden = !shouldShow
        canvas.isHidden = shouldShow || isFolderBrowserMode
        if shouldShow {
            refreshContinuousReadingWindow()
        } else {
            continuousReadingTask?.cancel()
            continuousReadingTask = nil
        }
        bottomZoomLabel.isHidden = shouldShow || isFolderBrowserMode || viewModel.currentImage == nil
    }

    private func refreshContinuousReadingWindow() {
        continuousReadingTask?.cancel()
        let viewModel = viewModel
        let focusedItemID = continuousReadingFocusID ?? viewModel.navigationState?.currentItem?.id
        continuousReadingTask = Task { [weak self, viewModel] in
            let pages = await viewModel.continuousReadingPages(centeredAt: focusedItemID)
            guard !Task.isCancelled, let self, self.settings.usesContinuousReading else { return }
            self.continuousReadingView.apply(
                pages: pages,
                currentItemID: focusedItemID
            )
        }
    }

    private func updateInspector(metadata: ImageMetadata?) {
        inspectorView.rootView = InspectorView(
            metadata: metadata,
            isDocked: isInspectorDocked,
            onToggleDock: { [weak self] in self?.toggleInspectorDock() },
            onClose: { [weak self] in self?.settings.showsInspector = false }
        )
    }

    private func toggleInspectorDock() {
        isInspectorDocked.toggle()
        updateInspector(metadata: viewModel.currentMetadata)
        updateInspectorLayout()
    }

    private func updateInspectorLayout() {
        let shouldReserveSidebar = isInspectorDocked
            && settings.showsInspector
            && viewModel.currentImage != nil
            && !isFolderBrowserMode
        canvasTrailingConstraint?.constant = shouldReserveSidebar ? -252 : 0
        inspectorView.layer?.cornerRadius = shouldReserveSidebar ? 0 : 8
        rootView.layoutSubtreeIfNeeded()
    }

    private func revealFilmstripOverlay() {
        guard filmstripIsEligible(pointerIsActive: true) else {
            hideFilmstripOverlay(immediately: true)
            return
        }
        cancelFilmstripAutoHide()
        filmstripOverlayView.isHidden = false

        if filmstripOverlayView.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                filmstripOverlayView.animator().alphaValue = 1
            }
        }

        scheduleFilmstripAutoHide()
    }

    private func cancelFilmstripAutoHide() {
        filmstripHideTimer?.invalidate()
        filmstripHideTimer = nil
        filmstripVisibilityGeneration += 1
    }

    private func filmstripIsEligible(pointerIsActive: Bool) -> Bool {
        Self.shouldDisplayFilmstripOverlay(
            isEnabled: settings.showsFilmstrip,
            hasLoadedImage: viewModel.currentImage != nil,
            canvasScale: canvas.scale,
            pointerIsActive: pointerIsActive
        )
    }

    private func scheduleFilmstripAutoHide() {
        guard Self.shouldAutoHideFilmstrip(
            isEnabled: settings.showsFilmstrip,
            pointerIsOverOverlay: isPointerOverFilmstrip
        ) else { return }
        let generation = filmstripVisibilityGeneration
        filmstripHideTimer = Timer.scheduledTimer(withTimeInterval: Self.overlayAutoHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.filmstripVisibilityGeneration == generation else { return }
                self.hideFilmstripOverlay()
            }
        }
    }

    private func hideFilmstripOverlay(immediately: Bool = false) {
        cancelFilmstripAutoHide()
        guard !filmstripOverlayView.isHidden else { return }

        if immediately {
            isPointerOverFilmstrip = false
            filmstripOverlayView.alphaValue = 0
            filmstripOverlayView.isHidden = true
            return
        }

        let generation = filmstripVisibilityGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.overlayFadeOutDuration
            filmstripOverlayView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.filmstripVisibilityGeneration == generation else { return }
                self.filmstripOverlayView.isHidden = true
            }
        }
    }

    private func revealPageControls() {
        guard Self.shouldDisplayPageControls(
            itemCount: viewModel.navigationState?.items.count ?? 0,
            isCropping: cropOverlay.isCropping
        ) else {
            hidePageControls(immediately: true)
            return
        }

        cancelPageControlsAutoHide()
        pageNavigationOverlayView.isHidden = false
        if pageNavigationOverlayView.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                pageNavigationOverlayView.animator().alphaValue = 1
            }
        }
        schedulePageControlsAutoHide()
    }

    private func cancelPageControlsAutoHide() {
        pageControlsHideTimer?.invalidate()
        pageControlsHideTimer = nil
        pageControlsVisibilityGeneration += 1
    }

    private func schedulePageControlsAutoHide() {
        guard Self.shouldAutoHidePageControls(
            pointerIsOverControls: isPointerOverPageControls
        ) else { return }
        let generation = pageControlsVisibilityGeneration
        pageControlsHideTimer = Timer.scheduledTimer(
            withTimeInterval: Self.overlayAutoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pageControlsVisibilityGeneration == generation else { return }
                self.hidePageControls()
            }
        }
    }

    private func hidePageControls(immediately: Bool = false) {
        cancelPageControlsAutoHide()
        guard !pageNavigationOverlayView.isHidden else { return }

        if immediately {
            pageNavigationOverlayView.alphaValue = 0
            pageNavigationOverlayView.isHidden = true
            return
        }

        let generation = pageControlsVisibilityGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.overlayFadeOutDuration
            pageNavigationOverlayView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.pageControlsVisibilityGeneration == generation else { return }
                self.pageNavigationOverlayView.isHidden = true
            }
        }
    }

    private func configureContentBars() {
        for bar in [titleBarView, bottomBarView] {
            bar.material = .headerView
            bar.blendingMode = .withinWindow
            bar.state = .active
            bar.isEmphasized = false
            bar.translatesAutoresizingMaskIntoConstraints = false
        }

        for divider in [titleBarDivider, bottomBarDivider] {
            divider.boxType = .separator
        }

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.addSubview(titleLabel)
        let browseCurrentFolderText = Self.titleBarBrowseFolderToolTip()
        configureTitleBarButton(
            titleBarGridButton,
            symbolName: "square.grid.2x2",
            accessibilityDescription: browseCurrentFolderText,
            action: #selector(browseCurrentImageFolder(_:))
        )
        titleBarGridButton.toolTip = browseCurrentFolderText
        titleBarControlsStack.orientation = .horizontal
        titleBarControlsStack.alignment = .centerY
        titleBarControlsStack.distribution = .fill
        titleBarControlsStack.spacing = 2
        titleBarControlsStack.translatesAutoresizingMaskIntoConstraints = false
        titleBarControlsStack.addArrangedSubview(titleBarGridButton)
        let moreText = AppStrings.text("titleBar.more")
        configureTitleBarButton(
            titleBarMoreButton,
            symbolName: "ellipsis.circle",
            accessibilityDescription: moreText,
            action: #selector(showMoreMenu(_:))
        )
        titleBarControlsStack.addArrangedSubview(titleBarMoreButton)
        titleBarView.addSubview(titleBarControlsStack)
        updateTitleBarControlAvailability()
        titleBarDoubleClickRecognizer.numberOfClicksRequired = 2
        titleBarDoubleClickRecognizer.delegate = self
        titleBarView.addGestureRecognizer(titleBarDoubleClickRecognizer)

        for label in [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel] {
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 1
        }
        bottomDimensionLabel.lineBreakMode = .byTruncatingTail
        bottomDimensionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bottomPageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomZoomLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomZoomLabel.toolTip = AppStrings.text("viewer.zoom.menu.tooltip")
        bottomZoomLabel.setAccessibilityRole(.button)
        bottomZoomLabel.setAccessibilityLabel(AppStrings.text("viewer.zoom.menu.accessibilityLabel"))
        bottomZoomLabel.addGestureRecognizer(bottomZoomClickRecognizer)
        let showInfoText = AppStrings.text("menu.view.showInfo")
        bottomInfoButton.image = NSImage(systemSymbolName: Self.bottomBarInfoSymbolName, accessibilityDescription: showInfoText)
        bottomInfoButton.bezelStyle = .toolbar
        bottomInfoButton.isBordered = false
        bottomInfoButton.toolTip = showInfoText
        bottomInfoButton.setAccessibilityLabel(showInfoText)
        bottomInfoButton.target = self
        bottomInfoButton.action = #selector(toggleInspector(_:))

        filmstripOverlayView.isHidden = true
        pageNavigationOverlayView.isHidden = true
        folderBrowserView.isHidden = true
    }

    private func configureTitleBarButton(
        _ button: HoverToolbarButton,
        symbolName: String,
        accessibilityDescription: String,
        action: Selector
    ) {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(symbolConfiguration)
        button.toolTip = accessibilityDescription
        button.setAccessibilityLabel(accessibilityDescription)
        button.target = self
        button.action = action
    }

    private func updateTitleBarControlAvailability(folderState: FolderRouteState? = nil) {
        titleBarGridButton.isEnabled = canToggleTitleBarGrid(folderState: folderState)
        let gridText: String
        if case .folder = currentRoute {
            gridText = AppStrings.text("titleBar.showImage")
        } else {
            gridText = AppStrings.text("titleBar.showFolder")
        }
        titleBarGridButton.toolTip = gridText
        titleBarGridButton.setAccessibilityLabel(gridText)
        titleBarGridButton.image?.accessibilityDescription = gridText
    }

    private func updateWindowTitle(viewerTitle: String) {
        let title: String
        let toolTip: String?
        if case .folder(let folderURL) = currentRoute {
            title = folderURL.lastPathComponent
            toolTip = folderURL.path
        } else {
            title = viewerTitle
            toolTip = nil
        }
        window?.title = title
        titleLabel.stringValue = title
        titleLabel.toolTip = toolTip
        titleLabel.setAccessibilityLabel(title)
        titleLabel.setAccessibilityHelp(toolTip)
    }

    @objc private func showMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let commands: [(String, Selector)] = [
            ("menu.image.rotateClockwise", #selector(rotateClockwise(_:))),
            ("menu.image.crop", #selector(startCropping(_:))),
            ("menu.view.showFilmstrip", #selector(toggleFilmstrip(_:))),
            ("menu.view.continuousReading", #selector(toggleContinuousReading(_:))),
            ("menu.view.showInfo", #selector(toggleInspector(_:))),
            ("menu.image.saveAs", #selector(saveEditsAs(_:))),
            ("menu.file.reveal", #selector(revealCurrentImageInFinder(_:))),
            ("menu.file.moveToTrash", #selector(moveCurrentImageToTrash(_:)))
        ]
        for (index, command) in commands.enumerated() {
            if index == 2 || index == 6 || index == 7 { menu.addItem(.separator()) }
            let item = NSMenuItem(
                title: AppStrings.text(command.0),
                action: command.1,
                keyEquivalent: ""
            )
            if let sourceItem = Self.menuItem(in: NSApp.mainMenu, matching: command.1) {
                item.keyEquivalent = sourceItem.keyEquivalent
                item.keyEquivalentModifierMask = sourceItem.keyEquivalentModifierMask
            }
            item.image = Self.moreMenuSymbol(for: command.1).flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: item.title)
            }
            item.target = self
            item.isEnabled = validateMenuItem(item)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    private static func menuItem(in menu: NSMenu?, matching action: Selector) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.action == action { return item }
            if let match = menuItem(in: item.submenu, matching: action) { return match }
        }
        return nil
    }

    private static func moreMenuSymbol(for action: Selector) -> String? {
        switch action {
        case #selector(rotateClockwise(_:)): return "rotate.right"
        case #selector(startCropping(_:)): return "crop"
        case #selector(toggleFilmstrip(_:)): return "rectangle.stack"
        case #selector(toggleContinuousReading(_:)): return "book.pages"
        case #selector(toggleInspector(_:)): return "info.circle"
        case #selector(saveEditsAs(_:)): return "square.and.arrow.down"
        case #selector(revealCurrentImageInFinder(_:)): return "folder"
        case #selector(moveCurrentImageToTrash(_:)): return "trash"
        default: return nil
        }
    }

    private func canToggleTitleBarGrid(folderState: FolderRouteState?) -> Bool {
        switch currentRoute {
        case .viewer:
            true
        case .folder:
            associatedViewerRoute(folderState: folderState) != nil
        case nil:
            false
        }
    }

    private func startFolderRetry() {
        guard folderRetryTask == nil else { return }
        folderRetryGeneration &+= 1
        let generation = folderRetryGeneration
        let folderBrowserViewModel = folderBrowserViewModel
        folderRetryTask = Task { [weak self, folderBrowserViewModel] in
            guard !Task.isCancelled else { return }
            await folderBrowserViewModel.retryOpenFolder()
            guard let self, self.folderRetryGeneration == generation else { return }
            self.folderRetryTask = nil
        }
    }

    private func stopFolderRetryTask() {
        folderRetryGeneration &+= 1
        folderRetryTask?.cancel()
        folderRetryTask = nil
    }

    private func invalidateFolderRetry() {
        stopFolderRetryTask()
        folderBrowserViewModel.invalidateOpenFolderRequest()
    }

    private func cancelFolderRetry() {
        stopFolderRetryTask()
        folderBrowserViewModel.cancelOpenFolderRequest()
    }

    private static func folderBrowserPresentation(
        session: FolderSession?,
        isLoading: Bool,
        loadErrorMessage: String?
    ) -> FolderBrowserPresentation {
        if isLoading { return .loading }
        if let loadErrorMessage { return .loadFailed(loadErrorMessage) }
        guard let session else { return .loading }
        if session.items.isEmpty { return .emptyFolder }
        if session.visibleItems.isEmpty { return .filteredEmpty }
        return .content
    }

    private func shouldRecognizeTitleBarDoubleClick(hitView: NSView?) -> Bool {
        hitView === titleBarView
    }

    static func canvasBackgroundColor() -> NSColor {
        .windowBackgroundColor
    }

    private func updateEmptyStatePresentation() {
        updateEmptyStatePresentation(
            hasCurrentImage: viewModel.currentImage != nil,
            loadPhase: viewModel.loadPhase,
            hasError: viewModel.errorMessage != nil
        )
    }

    private func updateEmptyStatePresentation(
        hasCurrentImage: Bool,
        loadPhase: ImageLoadPhase,
        hasError: Bool
    ) {
        emptyStateView.isHidden = isFolderBrowserMode || !Self.shouldDisplayEmptyState(
            hasCurrentImage: hasCurrentImage,
            loadPhase: loadPhase,
            hasError: hasError
        )
        errorStateView.isHidden = isFolderBrowserMode || !Self.shouldDisplayErrorState(
            hasCurrentImage: hasCurrentImage,
            hasError: hasError
        )

        let shouldHideStatusContent = isFolderBrowserMode || Self.shouldHideImageStatusContent(
            hasCurrentImage: hasCurrentImage
        )
        for view in [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel, bottomInfoButton] {
            view.isHidden = shouldHideStatusContent
        }
        inspectorView.isHidden = !Self.shouldDisplayInspector(
            isEnabled: settings.showsInspector,
            hasCurrentImage: hasCurrentImage
        ) || isFolderBrowserMode
        if hasCurrentImage && loadPhase == .full && !isFolderBrowserMode {
            showUsageHintIfNeeded()
        } else if !hasCurrentImage || isFolderBrowserMode {
            hideUsageHint()
        }
    }

    private func showUsageHintIfNeeded() {
        guard !settings.hasShownUsageHint, usageHintView.isHidden else { return }
        settings.hasShownUsageHint = true
        usageHintView.alphaValue = 1
        usageHintView.isHidden = false
        NSAccessibility.post(element: usageHintView, notification: .announcementRequested)
        usageHintTimer?.invalidate()
        usageHintTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideUsageHint() }
        }
    }

    private func hideUsageHint() {
        usageHintTimer?.invalidate()
        usageHintTimer = nil
        usageHintView.isHidden = true
    }

    private func revealFullScreenChromeIfNeeded() {
        guard isInFullScreen else { return }
        setFullScreenChromeVisible(true)
        fullScreenChromeHideTimer?.invalidate()
        fullScreenChromeHideTimer = Timer.scheduledTimer(
            withTimeInterval: Self.overlayAutoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.setFullScreenChromeVisible(false) }
        }
    }

    private func setFullScreenChromeVisible(_ visible: Bool) {
        titleBarHeightConstraint.constant = visible ? Self.titleBarHeight : 0
        bottomBarHeightConstraint.constant = visible ? Self.bottomBarHeight : 0
        titleBarView.isHidden = !visible
        titleBarDivider.isHidden = !visible
        bottomBarView.isHidden = !visible
        bottomBarDivider.isHidden = !visible
        rootView.needsLayout = true
    }

    private func announceLoadedImageIfNeeded(hasImage: Bool, loadPhase: ImageLoadPhase) {
        guard hasImage, loadPhase == .full,
              let url = viewModel.navigationState?.currentItem?.url.standardizedFileURL else {
            if !hasImage { lastAnnouncedLoadedURL = nil }
            return
        }
        guard lastAnnouncedLoadedURL != url else { return }
        lastAnnouncedLoadedURL = url
        let message = String(
            format: AppStrings.text("viewer.announcement.loaded"),
            url.lastPathComponent
        )
        if let accessibilityAnnouncementHandlerForTesting {
            accessibilityAnnouncementHandlerForTesting(message)
            return
        }
        NSAccessibility.post(
            element: canvas,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func enterFolderBrowserMode() {
        isFolderBrowserMode = true
        canvas.isHidden = true
        continuousReadingView.isHidden = true
        continuousReadingTask?.cancel()
        folderBrowserView.isHidden = false
        emptyStateView.isHidden = true
        errorStateView.isHidden = true
        hideFilmstripOverlay(immediately: true)
        hidePageControls(immediately: true)
        cropOverlay.isHidden = true
        cropControlsView.isHidden = true
        updateEmptyStatePresentation()
        updateInspectorLayout()
    }

    private func exitFolderBrowserMode() {
        guard isFolderBrowserMode || !folderBrowserView.isHidden || canvas.isHidden else { return }
        isFolderBrowserMode = false
        folderBrowserView.isHidden = true
        updateContinuousReadingPresentation()
        updateEmptyStatePresentation()
        updateInspectorLayout()
    }

    static func shouldDisplayEmptyState(
        hasCurrentImage: Bool,
        loadPhase: ImageLoadPhase,
        hasError: Bool
    ) -> Bool {
        !hasCurrentImage && loadPhase == .empty && !hasError
    }

    static func shouldHideImageStatusContent(hasCurrentImage: Bool) -> Bool {
        !hasCurrentImage
    }

    static func shouldDisplayErrorState(hasCurrentImage: Bool, hasError: Bool) -> Bool {
        !hasCurrentImage && hasError
    }

    static func shouldDisplayInspector(isEnabled: Bool, hasCurrentImage: Bool) -> Bool {
        isEnabled && hasCurrentImage
    }

    var isEmptyStateVisibleForTesting: Bool { !emptyStateView.isHidden }
    var isErrorStateVisibleForTesting: Bool { !errorStateView.isHidden }
    var isShowingRecoverableErrorForTesting: Bool {
        viewModel.currentImage == nil && viewModel.errorMessage != nil
    }
    var errorRetryButtonForTesting: NSButton? { errorStateView.retryButtonForTesting }

    var isImageStatusContentHiddenForTesting: Bool {
        [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel, bottomInfoButton]
            .allSatisfy(\.isHidden)
    }

    var isInspectorVisibleForTesting: Bool { !inspectorView.isHidden }
    var hasLoadedImageForTesting: Bool { viewModel.currentImage != nil }
    var canEditCurrentImageForTesting: Bool { viewModel.canEditCurrentImage }
    var hasUnsavedEditsForTesting: Bool { viewModel.hasUnsavedEdits }
    var isFolderBrowserVisibleForTesting: Bool { !folderBrowserView.isHidden }
    var folderBrowserIsOperatingForTesting: Bool { folderBrowserViewModel.isOperating }
    var isCanvasVisibleForTesting: Bool { !canvas.isHidden }
    var isFullScreenChromeVisibleForTesting: Bool {
        !titleBarView.isHidden && !bottomBarView.isHidden
    }
    func revealFullScreenChromeForTesting() { revealFullScreenChromeIfNeeded() }
    var isFilmstripVisibleForTesting: Bool { !filmstripOverlayView.isHidden }
    var isPageControlsVisibleForTesting: Bool { !pageNavigationOverlayView.isHidden }
    var folderBrowserItemCountForTesting: Int { folderBrowserView.testingItemCount }
    var folderBrowserOperationStatusTextForTesting: String? { folderBrowserView.testingOperationStatusText }
    var folderBrowserPresentationTitleForTesting: String? { folderBrowserView.testingPresentationTitle }
    var titleBarGridButtonForTesting: NSButton { titleBarGridButton }
    var titleBarControlsStackForTesting: NSStackView { titleBarControlsStack }
    var titleBarViewForTesting: NSView { titleBarView }
    var titleBarDoubleClickRecognizerForTesting: NSClickGestureRecognizer { titleBarDoubleClickRecognizer }

    func shouldRecognizeTitleBarDoubleClickForTesting(hitView: NSView) -> Bool {
        shouldRecognizeTitleBarDoubleClick(hitView: hitView)
    }

    func performTitleBarDoubleClickForTesting(hitView: NSView) {
        guard shouldRecognizeTitleBarDoubleClick(hitView: hitView) else { return }
        toggleWindowZoom(nil)
    }

    func requestOpenFromEmptyStateForTesting() {
        emptyStateView.performOpenForTesting()
    }

    func requestBrowseFolderFromEmptyStateForTesting() {
        emptyStateView.performBrowseFolderForTesting()
    }

    func requestOpenFromErrorStateForTesting() {
        errorStateView.performRetryForTesting()
    }

    func openFolderForTesting(_ folderURL: URL, items: [ImageItem]) {
        invalidateFolderRetry()
        hasAssignedOpenRequest = true
        currentRoute = .folder(folderURL.standardizedFileURL)
        associatedViewerURL = nil
        backRoute = nil
        forwardRoute = nil
        enterFolderBrowserMode()
        currentFolderBrowserItems = items
        folderBrowserView.apply(items: items, selectedIDs: [])
    }

    func openFolderForTesting(_ folderURL: URL, scannerItems: [ImageItem]) async {
        invalidateFolderRetry()
        hasAssignedOpenRequest = true
        currentRoute = .folder(folderURL.standardizedFileURL)
        associatedViewerURL = nil
        backRoute = nil
        forwardRoute = nil
        enterFolderBrowserMode()
        await folderBrowserViewModel.openFolder(folderURL)
    }

    func selectFolderBrowserItemsForTesting(_ selectedIDs: [ImageItem.ID]) {
        folderBrowserView.testingSelectItems(with: Set(selectedIDs))
    }

    func triggerFolderBrowserTrashForTesting() {
        folderBrowserView.testingTriggerTrash()
    }

    func triggerFolderBrowserMoveForTesting() {
        folderBrowserView.testingTriggerMove()
    }

    func triggerFolderBrowserRenameForTesting() {
        folderBrowserView.testingTriggerRename()
    }

    func triggerPrimaryFolderBrowserRecoveryForTesting() {
        folderBrowserView.testingTriggerPrimaryRecovery()
    }

    func triggerSecondaryFolderBrowserRecoveryForTesting() {
        folderBrowserView.testingTriggerSecondaryRecovery()
    }

    func requestFolderRetryForTesting() {
        startFolderRetry()
    }

    func openFirstFolderBrowserItemForTesting() {
        guard let firstItem = currentFolderBrowserItems.first else { return }
        folderBrowserView.onOpenItem?(firstItem)
    }

    func openFolderBrowserItemForTesting(at index: Int) {
        guard currentFolderBrowserItems.indices.contains(index) else { return }
        folderBrowserView.onOpenItem?(currentFolderBrowserItems[index])
    }

    var canGoBackForTesting: Bool { backRoute != nil && backRoute != currentRoute }
    var canGoForwardForTesting: Bool { forwardRoute != nil && forwardRoute != currentRoute }
    var lastOpenedFolderItemIDForTesting: ImageItem.ID? {
        folderBrowserViewModel.session?.lastOpenedItemID
    }
    var forwardViewerURLForTesting: URL? {
        guard case let .viewer(url) = forwardRoute else { return nil }
        return url
    }
    var associatedViewerURLForTesting: URL? { associatedViewerURL }
    var currentViewerRouteURLForTesting: URL? {
        guard case let .viewer(url) = currentRoute else { return nil }
        return url
    }
    var viewerNavigationURLForTesting: URL? {
        viewModel.navigationState?.currentItem?.url.standardizedFileURL
    }
    var displayedItemURLForTesting: URL? { displayedItemURL }
    var folderBrowserScrollOriginForTesting: NSPoint { folderBrowserView.testingScrollOrigin }

    func setFolderBrowserScrollOriginForTesting(_ origin: NSPoint) {
        folderBrowserView.testingSetScrollOrigin(origin)
    }

    var viewerNavigationURLsForTesting: [URL] {
        viewModel.navigationState?.items.map { $0.url.standardizedFileURL } ?? []
    }

    func setUnsavedChangesChoiceForTesting(_ choice: UnsavedChangesChoice?) {
        unsavedChangesChoiceForTesting = choice
    }

    func performTitleBarGridToggleForTesting() {
        browseCurrentImageFolder(nil)
    }

    func goBackForTesting() {
        goBack()
    }

    func goForwardForTesting() {
        goForward()
    }

    func performTitleBarBrowseCurrentFolderForTesting(items: [ImageItem]) {
        let folderURL = displayedItemURL?.deletingLastPathComponent()
            ?? items.first?.url.deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/", isDirectory: true)
        openFolderForTesting(folderURL, items: items)
    }

    func returnToEmptyStateAfterCancelledOpen() {
        guard viewModel.currentImage == nil, viewModel.errorMessage != nil else { return }
        viewModel.resetToEmptyState()
        hasAssignedOpenRequest = false
        updateEmptyStatePresentation()
    }

    func updateRecentItems(_ urls: [URL]) {
        emptyStateView.applyRecentItems(urls)
    }

    static func shouldDisplayFilmstripOverlay(
        isEnabled: Bool,
        hasLoadedImage: Bool,
        canvasScale: CGFloat,
        pointerIsActive: Bool
    ) -> Bool {
        isEnabled && hasLoadedImage && canvasScale <= 1.01 && pointerIsActive
    }

    static func shouldAutoHideFilmstrip(isEnabled: Bool, pointerIsOverOverlay: Bool) -> Bool {
        isEnabled && !pointerIsOverOverlay
    }

    static func shouldDisplayPageControls(itemCount: Int, isCropping: Bool) -> Bool {
        itemCount > 1 && !isCropping
    }

    static func pageControlAvailability(
        navigationState: NavigationState?,
        readingDirection: ReadingDirection = .leftToRight
    ) -> PageControlAvailability {
        guard let navigationState,
              let currentIndex = navigationState.currentIndex else {
            return PageControlAvailability(previous: false, next: false)
        }
        let leftToRight = PageControlAvailability(
            previous: currentIndex > 0,
            next: currentIndex < navigationState.items.count - 1
        )
        guard readingDirection == .rightToLeft else { return leftToRight }
        return PageControlAvailability(previous: leftToRight.next, next: leftToRight.previous)
    }

    static func shouldAutoHidePageControls(pointerIsOverControls: Bool) -> Bool {
        !pointerIsOverControls
    }

    static func dimensionText(pixelWidth: Int?, pixelHeight: Int?) -> String {
        guard let pixelWidth, let pixelHeight else { return "— × — px" }
        return "\(pixelWidth) × \(pixelHeight) px"
    }

    static func pageText(navigationState: NavigationState?) -> String {
        guard let navigationState,
              let currentIndex = navigationState.currentIndex else { return "0 / 0" }
        return "\(currentIndex + 1) / \(navigationState.items.count)"
    }

    static func zoomText(zoomScale: CGFloat) -> String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    static func zoomText(displayMode: ImageCanvasView.DisplayMode, pixelScale: CGFloat?) -> String {
        guard let pixelScale else {
            switch displayMode {
            case .fit: return AppStrings.text("viewer.zoom.fit")
            case .fitWidth: return AppStrings.text("viewer.zoom.fitWidth")
            case .manual: return "—%"
            }
        }
        let percentage = zoomText(zoomScale: pixelScale)
        if displayMode == .fit {
            return String(format: AppStrings.text("viewer.zoom.fitWithPercentage"), percentage)
        }
        if displayMode == .fitWidth {
            return String(format: AppStrings.text("viewer.zoom.fitWidthWithPercentage"), percentage)
        }
        return percentage
    }

    private func navigateToNextImage() {
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            guard let self else { return }
            if self.settings.readingDirection == .leftToRight {
                self.viewModel.showNext()
            } else {
                self.viewModel.showPrevious()
            }
        }
    }

    private func navigateToPreviousImage() {
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            guard let self else { return }
            if self.settings.readingDirection == .leftToRight {
                self.viewModel.showPrevious()
            } else {
                self.viewModel.showNext()
            }
        }
    }

    private func selectImage(_ item: ImageItem) {
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            self?.viewModel.show(item: item)
        }
    }

    private func performEdit(_ operation: EditOperation) {
        guard viewModel.canEditCurrentImage else {
            NSSound.beep()
            return
        }
        viewModel.applyEdit(operation)
    }

    private func confirmUnsavedEditsIfNeeded(
        for transition: UnsavedChangesTransition,
        perform action: () -> Void
    ) {
        guard viewModel.hasUnsavedEdits else {
            action()
            return
        }

        let choice = promptForUnsavedChanges(transition: transition)
        let saveSucceeded = choice == .save ? viewModel.saveCurrentEdits() : false
        let resolution = Self.resolveUnsavedChanges(choice: choice, saveSucceeded: saveSucceeded)

        guard resolution == .proceed else { return }
        if choice == .discard, !viewModel.discardCurrentEdits() {
            return
        }
        action()
    }

    private func promptForUnsavedChanges(transition: UnsavedChangesTransition) -> UnsavedChangesChoice {
        if let unsavedChangesChoiceForTesting {
            return unsavedChangesChoiceForTesting
        }
        let alert = NSAlert()
        alert.messageText = String(
            format: AppStrings.text("unsavedChanges.title"),
            transition.localizedDescription
        )
        alert.informativeText = AppStrings.text("unsavedChanges.message")
        alert.addButton(withTitle: AppStrings.text("unsavedChanges.button.save"))
        alert.addButton(withTitle: AppStrings.text("unsavedChanges.button.discard"))
        alert.addButton(withTitle: AppStrings.text("unsavedChanges.button.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undoEdit(_:)) {
            menuItem.title = viewModel.undoMenuTitle
            return !isFolderBrowserMode && viewModel.canUndo
        }
        if menuItem.action == #selector(redoEdit(_:)) {
            menuItem.title = viewModel.redoMenuTitle
            return !isFolderBrowserMode && viewModel.canRedo
        }
        if menuItem.action == #selector(toggleFilmstrip(_:)) {
            guard !isFolderBrowserMode else { return false }
            menuItem.state = settings.showsFilmstrip ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleInspector(_:)) {
            guard !isFolderBrowserMode else { return false }
            menuItem.state = settings.showsInspector ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleContinuousReading(_:)) {
            guard !isFolderBrowserMode, viewModel.currentImage != nil else { return false }
            menuItem.state = settings.usesContinuousReading ? .on : .off
            return true
        }

        guard let command = Self.menuCommand(for: menuItem.action) else {
            return true
        }

        return Self.isMenuCommandEnabled(
            command,
            hasCurrentItem: viewModel.navigationState?.currentItem != nil,
            hasCurrentImage: viewModel.currentImage != nil,
            canEditCurrentImage: viewModel.canEditCurrentImage,
            hasUnsavedEdits: viewModel.hasUnsavedEdits,
            isFolderBrowserMode: isFolderBrowserMode
        )
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        onWindowDidBecomeKey?(self)
        guard Self.shouldRefreshCurrentFileOnWindowActivation() else { return }
        refreshCurrentFileForExternalChanges()
        startExternalFileCheckTimer()
    }

    func windowWillClose(_ notification: Notification) {
        cancelFolderRetry()
        externalFileCheckTimer?.invalidate()
        externalFileCheckTimer = nil
        onWindowDidClose?(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        externalFileCheckTimer?.invalidate()
        externalFileCheckTimer = nil
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isInFullScreen = true
        fullScreenChromeHideTimer?.invalidate()
        fullScreenChromeHideTimer = nil
        setFullScreenChromeVisible(false)
        applySettings()
    }

    private func startExternalFileCheckTimer() {
        externalFileCheckTimer?.invalidate()
        externalFileCheckTimer = Timer.scheduledTimer(withTimeInterval: Self.externalFileCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentFileForExternalChanges()
            }
        }
    }

    private func refreshCurrentFileForExternalChanges() {
        Task { await viewModel.refreshCurrentFileIfNeeded() }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isInFullScreen = false
        fullScreenChromeHideTimer?.invalidate()
        fullScreenChromeHideTimer = nil
        setFullScreenChromeVisible(true)
        applySettings()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelCrop(nil)
        guard viewModel.hasUnsavedEdits else { return true }

        let choice = promptForUnsavedChanges(transition: .closing)
        let saveSucceeded = choice == .save ? viewModel.saveCurrentEdits() : false
        let resolution = Self.resolveUnsavedChanges(choice: choice, saveSucceeded: saveSucceeded)

        if choice == .discard, resolution == .proceed {
            return viewModel.discardCurrentEdits()
        }

        return resolution == .proceed
    }
}

private enum UnsavedChangesTransition {
    case opening
    case navigating
    case renaming
    case movingToTrash
    case closing

    var localizedDescription: String {
        switch self {
        case .opening:
            return AppStrings.text("unsavedChanges.transition.opening")
        case .navigating:
            return AppStrings.text("unsavedChanges.transition.navigating")
        case .renaming:
            return AppStrings.text("unsavedChanges.transition.renaming")
        case .movingToTrash:
            return AppStrings.text("unsavedChanges.transition.movingToTrash")
        case .closing:
            return AppStrings.text("unsavedChanges.transition.closing")
        }
    }
}
