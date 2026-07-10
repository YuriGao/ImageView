import AppKit
import Combine
import ImageViewCore
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    enum MenuCommand: Equatable {
        case fileOperationRequiringCurrentItem
        case startCropping
        case editOperation(EditOperation)
        case saveEdits
        case saveEditsAs
        case discardEdits
    }

    enum HUDVisibilityAction: Equatable {
        case showIndefinitely
        case showTemporarily
        case hide
    }

    enum KeyAction: Equatable {
        case showPrevious
        case showNext
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

    private let viewModel = ViewerViewModel()
    private let settings: AppSettings
    private let rootView = HUDTrackingView()
    private let canvas = ImageCanvasView()
    private let cropOverlay = CropOverlayView()
    private let errorOverlay = ErrorOverlayView()
    private let hudView = NSHostingView(rootView: HUDView(filename: "ImageView", positionText: "0 / 0", zoomText: "100%", hasUnsavedEdits: false, isPinned: true))
    private let toolsToolbarView = NSHostingView(rootView: ImageToolsToolbarView(
        state: ImageToolsToolbarState.state(hasImage: false, position: nil, itemCount: 0, isCropping: false),
        onPrevious: {}, onNext: {}, onRotate: {}, onCrop: {}, onMirror: {}, onTrash: {}
    ))
    private let inspectorView = NSHostingView(rootView: InspectorView(metadata: nil))
    private let filmstripView = FilmstripView()
    private var cancellables: Set<AnyCancellable> = []
    private var gestureCoordinator: GestureCoordinator?
    private var keyMonitor: Any?
    private var displayedItemURL: URL?
    private var hudHideWorkItem: DispatchWorkItem?
    private var hudVisibilityGeneration: UInt64 = 0
    private let hudAutoHideDelay: TimeInterval = 1.8

    convenience init(settings: AppSettings = .shared) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ImageView"
        self.init(window: window, settings: settings)
        setup()
    }

    init(window: NSWindow?, settings: AppSettings = .shared) {
        self.settings = settings
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func open(url: URL) {
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .opening) { [weak self] in
            guard let self else { return }
            Task { await self.viewModel.open(url: url) }
        }
    }

    private func setup() {
        window?.delegate = self
        window?.titlebarAppearsTransparent = true
        window?.center()
        rootView.wantsLayer = true
        rootView.onMouseMoved = { [weak self] in
            self?.refreshHUDForActivity()
        }
        canvas.autoresizingMask = [.width, .height]
        canvas.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = rootView
        rootView.addSubview(canvas)
        canvas.addSubview(errorOverlay)
        rootView.addSubview(hudView)
        rootView.addSubview(toolsToolbarView)
        rootView.addSubview(inspectorView)
        rootView.addSubview(filmstripView)
        rootView.addSubview(cropOverlay)
        errorOverlay.translatesAutoresizingMaskIntoConstraints = false
        hudView.translatesAutoresizingMaskIntoConstraints = false
        toolsToolbarView.translatesAutoresizingMaskIntoConstraints = false
        inspectorView.translatesAutoresizingMaskIntoConstraints = false
        filmstripView.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.isHidden = true
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: rootView.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            errorOverlay.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            errorOverlay.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            hudView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
            hudView.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            hudView.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 16),
            hudView.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -16),
            toolsToolbarView.topAnchor.constraint(equalTo: hudView.bottomAnchor, constant: 8),
            toolsToolbarView.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            toolsToolbarView.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 16),
            toolsToolbarView.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -16),
            inspectorView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            inspectorView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 64),
            inspectorView.bottomAnchor.constraint(lessThanOrEqualTo: filmstripView.topAnchor, constant: -16),
            filmstripView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            filmstripView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            filmstripView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -16),
            filmstripView.heightAnchor.constraint(equalToConstant: 36),
            cropOverlay.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            cropOverlay.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            cropOverlay.topAnchor.constraint(equalTo: canvas.topAnchor),
            cropOverlay.bottomAnchor.constraint(equalTo: canvas.bottomAnchor)
        ])

        canvas.onNext = { [weak self] in self?.navigateToNextImage() }
        canvas.onPrevious = { [weak self] in self?.navigateToPreviousImage() }
        canvas.onTransformChanged = { [weak self] scale in
            self?.refreshHUDForActivity(zoomScale: scale)
        }
        gestureCoordinator = GestureCoordinator(canvas: canvas)
        filmstripView.onSelect = { [weak self] item in
            self?.selectImage(item)
        }

        viewModel.$currentImage
            .sink { [weak self] image in
                self?.canvas.image = image
            }
            .store(in: &cancellables)

        viewModel.$displayTitle
            .sink { [weak self] title in
                self?.window?.title = title
            }
            .store(in: &cancellables)

        viewModel.$hasUnsavedEdits
            .sink { [weak self] _ in
                self?.refreshHUDForActivity()
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .sink { [weak self] message in
                self?.errorOverlay.stringValue = message ?? ""
                self?.refreshHUDForActivity()
            }
            .store(in: &cancellables)

        viewModel.$currentMetadata
            .sink { [weak self] metadata in
                self?.inspectorView.rootView = InspectorView(metadata: metadata)
            }
            .store(in: &cancellables)

        viewModel.$navigationState
            .sink { [weak self] state in
                guard let self else { return }
                let newURL = state?.currentItem?.url
                if Self.shouldResetCanvasTransform(from: self.displayedItemURL, to: newURL) {
                    self.canvas.resetViewTransform()
                }
                self.displayedItemURL = newURL?.standardizedFileURL
                self.filmstripView.apply(items: state?.items ?? [], current: state?.currentItem)
                self.refreshHUDForActivity()
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
        refreshHUDForActivity()
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
        guard viewModel.currentImage != nil,
              let imageDrawRect = canvas.imageDrawRect else {
            NSSound.beep()
            return
        }

        cropOverlay.beginCropping(in: imageDrawRect)
        updateToolsToolbar()
        window?.makeFirstResponder(cropOverlay)
    }

    @objc func applyCrop(_ sender: Any?) {
        guard cropOverlay.isCropping,
              let pixelCropRect = canvas.pixelCropRect(for: cropOverlay.cropRect) else {
            NSSound.beep()
            return
        }

        performEdit(.crop(pixelCropRect))
        cancelCrop(nil)
    }

    @objc func cancelCrop(_ sender: Any?) {
        cropOverlay.endCropping()
        updateToolsToolbar()
        window?.makeFirstResponder(canvas)
    }

    @objc func saveEdits(_ sender: Any?) {
        guard viewModel.currentImage != nil else {
            NSSound.beep()
            return
        }
        _ = viewModel.saveCurrentEdits()
    }

    @objc func saveEditsAs(_ sender: Any?) {
        guard viewModel.currentImage != nil, viewModel.hasUnsavedEdits else {
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
    }

    @objc func toggleInspector(_ sender: Any?) {
        settings.showsInspector.toggle()
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
            modifierFlags: event.modifierFlags
        ) {
        case .showPrevious:
            navigateToPreviousImage()
            return true
        case .showNext:
            navigateToNextImage()
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
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> KeyAction {
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

    static func hudVisibilityAction(isPinned: Bool, isActivity: Bool) -> HUDVisibilityAction {
        if isPinned {
            return .showIndefinitely
        }
        return isActivity ? .showTemporarily : .hide
    }

    static func shouldScheduleHUDHide(isPinned: Bool) -> Bool {
        !isPinned
    }

    static func shouldShowToolsToolbar(isHUDVisible: Bool, isCropping: Bool) -> Bool {
        isHUDVisible && !isCropping
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
        hasUnsavedEdits: Bool
    ) -> Bool {
        switch command {
        case .fileOperationRequiringCurrentItem:
            return hasCurrentItem
        case .startCropping:
            return hasCurrentImage
        case .editOperation:
            return hasCurrentImage
        case .saveEdits, .saveEditsAs, .discardEdits:
            return hasCurrentImage && hasUnsavedEdits
        }
    }

    private func updateHUD(zoomScale: CGFloat? = nil) {
        let scale = zoomScale ?? canvas.scale
        hudView.rootView = HUDView(
            filename: viewModel.currentFilename,
            positionText: viewModel.positionText,
            zoomText: "\(Int((scale * 100).rounded()))%",
            hasUnsavedEdits: viewModel.hasUnsavedEdits,
            isPinned: settings.pinsHUD
        )
    }

    private func refreshHUDForActivity(zoomScale: CGFloat? = nil) {
        updateHUD(zoomScale: zoomScale)

        switch Self.hudVisibilityAction(isPinned: settings.pinsHUD, isActivity: true) {
        case .showIndefinitely:
            showPinnedHUD()
        case .showTemporarily:
            showHUDTemporarily()
        case .hide:
            hideHUDIfUnpinned(generation: hudVisibilityGeneration)
        }
    }

    private func showPinnedHUD() {
        hudVisibilityGeneration += 1
        hudHideWorkItem?.cancel()
        hudHideWorkItem = nil
        hudView.isHidden = false
        hudView.alphaValue = 1
        updateToolsToolbar(isHUDVisible: true)
    }

    private func showHUDTemporarily() {
        hudVisibilityGeneration += 1
        let generation = hudVisibilityGeneration
        hudHideWorkItem?.cancel()
        hudView.isHidden = false
        hudView.alphaValue = 1
        updateToolsToolbar(isHUDVisible: true)

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideHUDIfUnpinned(generation: generation)
        }
        hudHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hudAutoHideDelay, execute: workItem)
    }

    private func hideHUDIfUnpinned(generation: UInt64) {
        guard !settings.pinsHUD,
              generation == hudVisibilityGeneration else {
            return
        }

        hudHideWorkItem = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hudView.animator().alphaValue = 0
            toolsToolbarView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.settings.pinsHUD,
                      generation == self.hudVisibilityGeneration else {
                    return
                }
                self.hudView.isHidden = true
                self.toolsToolbarView.isHidden = true
            }
        }
    }

    private func updateToolsToolbar(isHUDVisible: Bool? = nil) {
        let navigationState = viewModel.navigationState
        let toolbarState = ImageToolsToolbarState.state(
            hasImage: viewModel.currentImage != nil,
            position: navigationState?.currentIndex,
            itemCount: navigationState?.items.count ?? 0,
            isCropping: cropOverlay.isCropping
        )
        toolsToolbarView.rootView = ImageToolsToolbarView(
            state: toolbarState,
            onPrevious: { [weak self] in self?.navigateToPreviousImage() },
            onNext: { [weak self] in self?.navigateToNextImage() },
            onRotate: { [weak self] in self?.rotateClockwise(nil) },
            onCrop: { [weak self] in self?.startCropping(nil) },
            onMirror: { [weak self] in self?.mirrorHorizontal(nil) },
            onTrash: { [weak self] in self?.moveCurrentImageToTrash(nil) }
        )

        let shouldShow = Self.shouldShowToolsToolbar(
            isHUDVisible: isHUDVisible ?? !hudView.isHidden,
            isCropping: cropOverlay.isCropping
        )
        toolsToolbarView.isHidden = !shouldShow
        toolsToolbarView.alphaValue = shouldShow ? 1 : 0
    }

    private func confirmMoveCurrentImageToTrash() -> Bool {
        guard let item = viewModel.navigationState?.currentItem else {
            NSSound.beep()
            return false
        }
        guard settings.confirmsDelete else { return true }

        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = "This will move \"\(item.url.lastPathComponent)\" to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func applySettings() {
        canvas.backgroundColor = Self.canvasBackgroundColor(
            isFullScreen: window?.styleMask.contains(.fullScreen) == true,
            usesBlackFullscreenBackground: settings.usesBlackFullscreenBackground
        )
        filmstripView.isHidden = !settings.showsFilmstrip
        inspectorView.isHidden = !settings.showsInspector
        refreshHUDForActivity()
    }

    static func canvasBackgroundColor(isFullScreen: Bool, usesBlackFullscreenBackground: Bool) -> NSColor {
        isFullScreen && !usesBlackFullscreenBackground ? .windowBackgroundColor : .black
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
        guard viewModel.currentImage != nil else {
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
        alert.messageText = "Save changes before \(transition.description)?"
        alert.informativeText = "You have unsaved edits for the current image."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

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
            menuItem.state = settings.showsFilmstrip ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleInspector(_:)) {
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
            hasUnsavedEdits: viewModel.hasUnsavedEdits
        )
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowDidEnterFullScreen(_ notification: Notification) {
        applySettings()
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

    var description: String {
        switch self {
        case .opening:
            return "opening another image"
        case .navigating:
            return "changing images"
        case .renaming:
            return "renaming this file"
        case .movingToTrash:
            return "moving this file to the Trash"
        case .closing:
            return "closing the window"
        }
    }
}
