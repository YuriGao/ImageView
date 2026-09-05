import AppKit
import ImageViewCore
import SwiftUI

extension MainWindowController {
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

    @objc func copyCurrentImage(_ sender: Any?) {
        guard let image = viewModel.currentImage,
              Self.writeImage(image.cgImage, to: .general) else {
            NSSound.beep()
            return
        }
    }

    @discardableResult
    static func writeImage(_ cgImage: CGImage, to pasteboard: NSPasteboard) -> Bool {
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
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
        runImageOperation { [viewModel] in _ = await viewModel.saveCurrentEdits() }
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
        runImageOperation { [viewModel] in _ = await viewModel.saveCurrentEdits(to: url, format: format) }
    }

    @objc func discardEdits(_ sender: Any?) {
        guard imageOperationTask == nil else { return }
        guard viewModel.currentImage != nil else {
            NSSound.beep()
            return
        }
        _ = viewModel.discardCurrentEdits()
    }

    @objc func undoEdit(_ sender: Any?) {
        runImageOperation { [viewModel] in if !(await viewModel.undoEdit()) { NSSound.beep() } }
    }

    @objc func redoEdit(_ sender: Any?) {
        runImageOperation { [viewModel] in if !(await viewModel.redoEdit()) { NSSound.beep() } }
    }

    func renameContextItem(_ item: ImageItem) {
        performWithCurrentItem(item) { [weak self] in
            self?.renameCurrentImage(nil)
        }
    }

    func trashContextItem(_ item: ImageItem) {
        performWithCurrentItem(item) { [weak self] in
            self?.moveCurrentImageToTrash(nil)
        }
    }

    func performWithCurrentItem(_ item: ImageItem, action: @escaping () -> Void) {
        if viewModel.navigationState?.currentItem?.id == item.id {
            action()
            return
        }
        cancelCrop(nil)
        confirmUnsavedEditsIfNeeded(for: .navigating) { [weak self] in
            guard let self else { return }
            self.viewModel.show(item: item)
            action()
        }
    }

    func copyPaths(_ urls: [URL]) {
        guard Self.writePaths(urls, to: .general) else { NSSound.beep(); return }
    }

    @discardableResult
    static func writePaths(_ urls: [URL], to pasteboard: NSPasteboard) -> Bool {
        guard !urls.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func moveSelectedFolderBrowserItemsToTrash() {
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

    func moveSelectedFolderBrowserItemsToFolder() {
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

    func confirmUnsavedEditsForSelectedViewerIfNeeded(
        _ selectedItems: [ImageItem],
        transition: UnsavedChangesTransition,
        perform action: @escaping () -> Void
    ) {
        let selectedURLs = Set(selectedItems.map { $0.url.standardizedFileURL })
        guard let viewerURL = viewModel.navigationState?.currentItem?.url.standardizedFileURL,
              selectedURLs.contains(viewerURL) else {
            action()
            return
        }
        confirmUnsavedEditsIfNeeded(for: transition, perform: action)
    }

    func renameSelectedFolderBrowserItems() {
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

    func confirmMoveCurrentImageToTrash() -> Bool {
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

    func confirmMoveSelectedFolderBrowserItemsToTrash(count: Int) -> Bool {
        guard settings.confirmsDelete else { return true }

        let alert = NSAlert()
        alert.messageText = String(format: AppStrings.text("folderBrowser.confirmTrash.title"), count)
        alert.informativeText = AppStrings.text("folderBrowser.confirmTrash.message")
        alert.addButton(withTitle: AppStrings.text("folderBrowser.confirmTrash.button"))
        alert.addButton(withTitle: AppStrings.text("folderBrowser.confirmTrash.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func chooseDestinationFolderForBatchMove() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = AppStrings.text("folderBrowser.movePanel.prompt")
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseMoveConflict(names: [String]) -> MoveConflictChoice {
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

    func showBatchRenameSheet(
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

    func performEdit(_ operation: EditOperation) {
        guard viewModel.canEditCurrentImage else {
            NSSound.beep()
            return
        }
        runImageOperation { [viewModel] in await viewModel.applyEdit(operation) }
    }

    func confirmUnsavedEditsIfNeeded(
        for transition: UnsavedChangesTransition,
        perform action: @escaping () -> Void
    ) {
        guard imageOperationTask == nil, !viewModel.isProcessingImage else { NSSound.beep(); return }
        guard viewModel.hasUnsavedEdits else {
            action()
            return
        }
        switch promptForUnsavedChanges(transition: transition) {
        case .save:
            runImageOperation { [viewModel] in
                if await viewModel.saveCurrentEdits() { action() }
            }
        case .discard:
            if viewModel.discardCurrentEdits() { action() }
        case .cancel:
            break
        }
    }

    func runImageOperation(_ operation: @escaping @MainActor () async -> Void) {
        guard imageOperationTask == nil, !viewModel.isProcessingImage else { NSSound.beep(); return }
        imageOperationTask = Task { [weak self] in
            await operation()
            self?.imageOperationTask = nil
        }
    }

    func waitForImageOperationForTesting() async {
        await imageOperationTask?.value
    }

    func promptForUnsavedChanges(transition: UnsavedChangesTransition) -> UnsavedChangesChoice {
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
    }}

enum UnsavedChangesTransition {
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
