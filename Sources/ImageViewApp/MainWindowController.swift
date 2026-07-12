import AppKit
import Combine
import ImageViewCore
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    static let externalFileCheckInterval: TimeInterval = 2
    static let titleBarHeight: CGFloat = 32
    static let bottomBarHeight: CGFloat = 28
    static let bottomBarInfoSymbolName = "info.circle"
    static let bottomBarStatusToInfoSpacing: CGFloat = 8
    static let filmstripOverlayHeight: CGFloat = 98
    static let overlayAutoHideDelay: TimeInterval = 1.8
    static let overlayFadeOutDuration: TimeInterval = 0.18
    static func titleBarBrowseFolderToolTip(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        AppStrings.text("titleBar.browseCurrentFolder", preferredLanguages: preferredLanguages)
    }

    var onSuccessfulOpen: ((URL) -> Void)? {
        didSet { viewModel.onSuccessfulOpen = onSuccessfulOpen }
    }
    var onOpenRequested: (() -> Void)?
    var onBrowseFolderRequested: (() -> Void)?
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

    struct BatchActionDialogProvider {
        var confirmTrash: ((Int) -> Bool)?
        var chooseDestinationFolder: (() -> URL?)?
        var requestRenameParameters: (([ImageItem], @escaping (BatchRenameSheetController.RenameParameters) -> Void) -> Void)?

        init(
            confirmTrash: ((Int) -> Bool)? = nil,
            chooseDestinationFolder: (() -> URL?)? = nil,
            requestRenameParameters: (([ImageItem], @escaping (BatchRenameSheetController.RenameParameters) -> Void) -> Void)? = nil
        ) {
            self.confirmTrash = confirmTrash
            self.chooseDestinationFolder = chooseDestinationFolder
            self.requestRenameParameters = requestRenameParameters
        }
    }

    struct PageControlAvailability: Equatable {
        let previous: Bool
        let next: Bool
    }

    private enum ContentRoute: Equatable {
        case viewer(URL)
        case folder(URL)
    }

    private let viewModel = ViewerViewModel()
    private let folderBrowserViewModel: FolderBrowserViewModel
    private let settings: AppSettings
    private let rootView = RootInteractionView()
    private let titleBarView = NSVisualEffectView()
    private let titleBarDivider = NSBox()
    private let titleLabel = NSTextField(labelWithString: "ImageView")
    private let titleBarGridButton = NSButton()
    private let canvas = ImageCanvasView()
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
    private let bottomInfoButton = NSButton()
    private let filmstripOverlayView = FilmstripOverlayView()
    private let filmstripView = FilmstripView()
    private let pageNavigationOverlayView = PageNavigationOverlayView()
    private var cancellables: Set<AnyCancellable> = []
    private var gestureCoordinator: GestureCoordinator?
    private var keyMonitor: Any?
    private var displayedItemURL: URL?
    private var externalFileCheckTimer: Timer?
    private var filmstripHideTimer: Timer?
    private var filmstripVisibilityGeneration = 0
    private var isPointerOverFilmstrip = false
    private var pageControlsHideTimer: Timer?
    private var pageControlsVisibilityGeneration = 0
    private var isPointerOverPageControls = false
    private var isFolderBrowserMode = false
    private var currentFolderBrowserItems: [ImageItem] = []
    private var currentRoute: ContentRoute?
    private var backRoute: ContentRoute?
    private var forwardRoute: ContentRoute?
    private var activeBatchRenameSheet: BatchRenameSheetController?
    var batchActionDialogProviderForTesting: BatchActionDialogProvider?

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

    func open(url: URL) {
        hasAssignedOpenRequest = true
        currentRoute = .viewer(url.standardizedFileURL)
        backRoute = nil
        forwardRoute = nil
        openImageUsingExistingPipeline(url)
    }

    private func openImageUsingExistingPipeline(_ url: URL) {
        exitFolderBrowserMode()
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .opening) { [weak self] in
            guard let self else { return }
            Task { await self.viewModel.open(url: url) }
        }
    }

    func openFolder(url: URL) {
        hasAssignedOpenRequest = true
        currentRoute = .folder(url.standardizedFileURL)
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
        errorStateView.onRetryRequested = { [weak self] in
            self?.onOpenRequested?()
        }
        rootView.onPointerMoved = { [weak self] in
            guard let self, !self.isFolderBrowserMode else { return }
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
        bottomBarView.addSubview(bottomDimensionLabel)
        bottomBarView.addSubview(bottomPageLabel)
        bottomBarView.addSubview(bottomZoomLabel)
        bottomBarView.addSubview(bottomInfoButton)
        filmstripOverlayView.addSubview(filmstripView)
        rootView.addSubview(cropOverlay)
        rootView.addSubview(cropControlsView)
        folderBrowserView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        errorStateView.translatesAutoresizingMaskIntoConstraints = false
        inspectorView.translatesAutoresizingMaskIntoConstraints = false
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
        NSLayoutConstraint.activate([
            titleBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            titleBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            titleBarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            titleBarView.heightAnchor.constraint(equalToConstant: Self.titleBarHeight),
            titleBarDivider.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            titleBarDivider.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            titleBarDivider.bottomAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            titleBarDivider.heightAnchor.constraint(equalToConstant: 1),
            titleLabel.centerXAnchor.constraint(equalTo: titleBarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleBarView.leadingAnchor, constant: 72),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleBarView.trailingAnchor, constant: -72),
            titleBarGridButton.leadingAnchor.constraint(equalTo: titleBarView.leadingAnchor, constant: 72),
            titleBarGridButton.centerYAnchor.constraint(equalTo: titleBarView.centerYAnchor),
            titleBarGridButton.widthAnchor.constraint(equalToConstant: 22),
            titleBarGridButton.heightAnchor.constraint(equalToConstant: 22),
            bottomBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            bottomBarView.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            bottomBarDivider.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            bottomBarDivider.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            bottomBarDivider.topAnchor.constraint(equalTo: bottomBarView.topAnchor),
            bottomBarDivider.heightAnchor.constraint(equalToConstant: 1),
            canvas.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),
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
        canvas.onTransformChanged = { [weak self] scale in
            guard let self else { return }
            self.updateZoomStatus(zoomScale: scale)
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
        folderBrowserView.onMoveToTrash = { [weak self] in
            self?.moveSelectedFolderBrowserItemsToTrash()
        }
        folderBrowserView.onMoveToFolder = { [weak self] in
            self?.moveSelectedFolderBrowserItemsToFolder()
        }
        folderBrowserView.onBatchRename = { [weak self] in
            self?.renameSelectedFolderBrowserItems()
        }

        viewModel.$currentImage
            .sink { [weak self] image in
                guard let self else { return }
                self.canvas.image = image
                if image == nil {
                    self.hideFilmstripOverlay(immediately: true)
                }
                guard self.settings.animatesNavigationTransitions,
                      image != nil else { return }
                self.canvas.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    self.canvas.animator().alphaValue = 1
                }
            }
            .store(in: &cancellables)

        folderBrowserViewModel.$session
            .sink { [weak self] session in
                guard let self else { return }
                let items = session?.visibleItems ?? []
                if self.currentFolderBrowserItems != items {
                    self.currentFolderBrowserItems = items
                    self.folderBrowserView.applyItems(items)
                }
                self.folderBrowserView.applySelection(Set(session?.selectedItemIDs ?? []))
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            folderBrowserViewModel.$operationMessage,
            folderBrowserViewModel.$operationFailures,
            folderBrowserViewModel.$isOperating
        )
            .sink { [weak self] message, failures, isOperating in
                self?.folderBrowserView.applyOperationStatus(
                    message: message,
                    failures: failures,
                    isOperating: isOperating
                )
            }
            .store(in: &cancellables)

        viewModel.$displayTitle
            .sink { [weak self] title in
                self?.window?.title = title
                self?.titleLabel.stringValue = title
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
                self?.updateEmptyStatePresentation(
                    hasCurrentImage: image != nil,
                    loadPhase: loadPhase,
                    hasError: errorMessage != nil
                )
            }
            .store(in: &cancellables)

        viewModel.$currentMetadata
            .sink { [weak self] metadata in
                self?.inspectorView.rootView = InspectorView(metadata: metadata)
                self?.updateDimensionStatus(metadata: metadata)
            }
            .store(in: &cancellables)

        viewModel.$navigationState
            .sink { [weak self] state in
                guard let self else { return }
                let newURL = state?.currentItem?.url
                let didNavigate = self.displayedItemURL != nil
                    && Self.shouldResetCanvasTransform(from: self.displayedItemURL, to: newURL)
                if Self.shouldResetCanvasTransform(from: self.displayedItemURL, to: newURL) {
                    self.canvas.resetViewTransform()
                }
                self.displayedItemURL = newURL?.standardizedFileURL
                if case .viewer = self.currentRoute, let newURL {
                    self.currentRoute = .viewer(newURL.standardizedFileURL)
                }
                self.filmstripView.apply(items: state?.items ?? [], current: state?.currentItem)
                let availability = Self.pageControlAvailability(navigationState: state)
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
        updateZoomStatus()
    }

    override func keyDown(with event: NSEvent) {
        guard !handleKeyDown(event) else { return }
        super.keyDown(with: event)
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
        if folderBrowserViewModel.session?.folderURL.standardizedFileURL == folderURL {
            showRoute(.folder(folderURL), recordHistory: false)
            return
        }

        currentRoute = .folder(folderURL)
        enterFolderBrowserMode()
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

    private func associatedViewerRoute() -> ContentRoute? {
        if let lastOpenedItemID = folderBrowserViewModel.session?.lastOpenedItemID,
           let item = folderBrowserViewModel.session?.items.first(where: { $0.id == lastOpenedItemID }) {
            return .viewer(item.url.standardizedFileURL)
        }
        if let displayedItemURL {
            return .viewer(displayedItemURL.standardizedFileURL)
        }
        if case let .viewer(url)? = backRoute ?? forwardRoute {
            return .viewer(url)
        }
        return nil
    }

    private func openFolderBrowserItem(_ item: ImageItem) {
        folderBrowserViewModel.recordOpenedItem(item)
        showRoute(.viewer(item.url.standardizedFileURL), recordHistory: true)
        hasAssignedOpenRequest = true
        openImageUsingExistingPipeline(item.url)
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

        folderBrowserViewModel.moveSelectedToTrash()
    }

    private func moveSelectedFolderBrowserItemsToFolder() {
        guard !folderBrowserViewModel.selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        let destination = batchActionDialogProviderForTesting?.chooseDestinationFolder?()
            ?? chooseDestinationFolderForBatchMove()
        guard let destination else { return }

        folderBrowserViewModel.moveSelected(to: destination, conflictPolicy: .skip)
    }

    private func renameSelectedFolderBrowserItems() {
        let selectedItems = folderBrowserViewModel.selectedItems
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }

        let confirm: (BatchRenameSheetController.RenameParameters) -> Void = { [weak self] parameters in
            self?.folderBrowserViewModel.renameSelected(
                baseName: parameters.baseName,
                startNumber: parameters.startNumber,
                padding: parameters.padding
            )
        }

        if let requestRenameParameters = batchActionDialogProviderForTesting?.requestRenameParameters {
            requestRenameParameters(selectedItems, confirm)
        } else {
            showBatchRenameSheet(items: selectedItems, onConfirm: confirm)
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
        case #selector(actualSize(_:)), #selector(zoomToFit(_:)):
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

    private func updateZoomStatus(zoomScale: CGFloat? = nil) {
        bottomZoomLabel.stringValue = Self.zoomText(zoomScale: zoomScale ?? canvas.scale)
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

    private func showBatchRenameSheet(
        items: [ImageItem],
        onConfirm: @escaping (BatchRenameSheetController.RenameParameters) -> Void
    ) {
        let controller = BatchRenameSheetController(items: items)
        controller.onConfirm = { [weak self] parameters in
            onConfirm(parameters)
            self?.activeBatchRenameSheet = nil
        }

        guard let sheet = controller.window, let window else {
            return
        }
        activeBatchRenameSheet = controller
        window.beginSheet(sheet) { [weak self] _ in
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
        bottomInfoButton.state = settings.showsInspector ? .on : .off
        updateDimensionStatus(metadata: viewModel.currentMetadata)
        updatePageStatus(navigationState: viewModel.navigationState)
        updateZoomStatus()
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
        titleBarGridButton.translatesAutoresizingMaskIntoConstraints = false
        let browseCurrentFolderText = Self.titleBarBrowseFolderToolTip()
        titleBarGridButton.image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: browseCurrentFolderText
        )
        titleBarGridButton.bezelStyle = .toolbar
        titleBarGridButton.isBordered = false
        titleBarGridButton.toolTip = browseCurrentFolderText
        titleBarGridButton.setAccessibilityLabel(browseCurrentFolderText)
        titleBarGridButton.target = self
        titleBarGridButton.action = #selector(browseCurrentImageFolder(_:))
        titleBarView.addSubview(titleBarGridButton)
        let titleBarDoubleClick = NSClickGestureRecognizer(target: self, action: #selector(toggleWindowZoom(_:)))
        titleBarDoubleClick.numberOfClicksRequired = 2
        titleBarView.addGestureRecognizer(titleBarDoubleClick)

        for label in [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel] {
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 1
        }
        bottomDimensionLabel.lineBreakMode = .byTruncatingTail
        bottomDimensionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bottomPageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomZoomLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
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
    }

    private func enterFolderBrowserMode() {
        isFolderBrowserMode = true
        canvas.isHidden = true
        folderBrowserView.isHidden = false
        emptyStateView.isHidden = true
        errorStateView.isHidden = true
        hideFilmstripOverlay(immediately: true)
        hidePageControls(immediately: true)
        cropOverlay.isHidden = true
        cropControlsView.isHidden = true
        updateEmptyStatePresentation()
    }

    private func exitFolderBrowserMode() {
        guard isFolderBrowserMode || !folderBrowserView.isHidden || canvas.isHidden else { return }
        isFolderBrowserMode = false
        folderBrowserView.isHidden = true
        canvas.isHidden = false
        updateEmptyStatePresentation()
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
    var isFolderBrowserVisibleForTesting: Bool { !folderBrowserView.isHidden }
    var isCanvasVisibleForTesting: Bool { !canvas.isHidden }
    var isFilmstripVisibleForTesting: Bool { !filmstripOverlayView.isHidden }
    var isPageControlsVisibleForTesting: Bool { !pageNavigationOverlayView.isHidden }
    var folderBrowserItemCountForTesting: Int { folderBrowserView.testingItemCount }
    var folderBrowserOperationStatusTextForTesting: String? { folderBrowserView.testingOperationStatusText }

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
        hasAssignedOpenRequest = true
        currentRoute = .folder(folderURL.standardizedFileURL)
        backRoute = nil
        forwardRoute = nil
        enterFolderBrowserMode()
        currentFolderBrowserItems = items
        folderBrowserView.apply(items: items, selectedIDs: [])
    }

    func openFolderForTesting(_ folderURL: URL, scannerItems: [ImageItem]) async {
        hasAssignedOpenRequest = true
        currentRoute = .folder(folderURL.standardizedFileURL)
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

    static func pageControlAvailability(navigationState: NavigationState?) -> PageControlAvailability {
        guard let navigationState,
              let currentIndex = navigationState.currentIndex else {
            return PageControlAvailability(previous: false, next: false)
        }
        return PageControlAvailability(
            previous: currentIndex > 0,
            next: currentIndex < navigationState.items.count - 1
        )
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

    private func navigateToNextImage() {
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            self?.viewModel.showNext()
        }
    }

    private func navigateToPreviousImage() {
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            self?.viewModel.showPrevious()
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
        externalFileCheckTimer?.invalidate()
        externalFileCheckTimer = nil
        onWindowDidClose?(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        externalFileCheckTimer?.invalidate()
        externalFileCheckTimer = nil
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
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
