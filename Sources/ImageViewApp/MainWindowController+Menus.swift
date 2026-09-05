import AppKit
import ImageViewCore
import SwiftUI

extension MainWindowController {
    @objc func setZoomPercentage(_ sender: NSMenuItem) {
        canvas.setManualPercentage(CGFloat(sender.tag))
    }

    @objc func setCustomZoomPercentage(_ sender: NSMenuItem) {
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

    @objc func showZoomMenu(_ sender: Any?) {
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

    func makeImageContextMenu() -> NSMenu? {
        guard !isFolderBrowserMode,
              viewModel.navigationState?.currentItem != nil,
              viewModel.currentImage != nil,
              !cropOverlay.isCropping else {
            return nil
        }

        let menu = NSMenu()
        menu.addItem(contextMenuItem("menu.file.copyImage", action: #selector(copyCurrentImage(_:))))
        menu.addItem(contextMenuItem("menu.file.copyPath", action: #selector(copyCurrentImagePath(_:))))
        menu.addItem(contextMenuItem("menu.file.reveal", action: #selector(revealCurrentImageInFinder(_:))))
        menu.addItem(.separator())

        let zoomItem = NSMenuItem(title: AppStrings.text("viewer.contextMenu.zoom"), action: nil, keyEquivalent: "")
        let zoomMenu = NSMenu(title: zoomItem.title)
        let fitItem = contextMenuItem("menu.view.zoomToFit", action: #selector(zoomToFit(_:)))
        fitItem.state = canvas.displayMode == .fit ? .on : .off
        zoomMenu.addItem(fitItem)
        let fitWidthItem = contextMenuItem("menu.view.zoomToFitWidth", action: #selector(zoomToFitWidth(_:)))
        fitWidthItem.state = canvas.displayMode == .fitWidth ? .on : .off
        zoomMenu.addItem(fitWidthItem)
        let actualSizeItem = contextMenuItem("menu.view.actualSize", action: #selector(actualSize(_:)))
        if canvas.displayMode == .manual,
           let pixelScale = canvas.pixelScale,
           abs(pixelScale - 1) < 0.005 {
            actualSizeItem.state = .on
        }
        zoomMenu.addItem(actualSizeItem)
        zoomItem.submenu = zoomMenu
        menu.addItem(zoomItem)
        menu.addItem(.separator())

        menu.addItem(contextMenuItem("menu.image.rotateClockwise", action: #selector(rotateClockwise(_:))))
        menu.addItem(contextMenuItem("menu.image.rotateCounterclockwise", action: #selector(rotateCounterClockwise(_:))))
        let flipItem = NSMenuItem(title: AppStrings.text("viewer.contextMenu.flip"), action: nil, keyEquivalent: "")
        let flipMenu = NSMenu(title: flipItem.title)
        flipMenu.addItem(contextMenuItem("menu.image.flipHorizontal", action: #selector(mirrorHorizontal(_:))))
        flipMenu.addItem(contextMenuItem("menu.image.flipVertical", action: #selector(mirrorVertical(_:))))
        flipItem.submenu = flipMenu
        menu.addItem(flipItem)
        menu.addItem(contextMenuItem("menu.image.crop", action: #selector(startCropping(_:))))

        if viewModel.hasUnsavedEdits {
            menu.addItem(.separator())
            menu.addItem(contextMenuItem("menu.image.saveEdits", action: #selector(saveEdits(_:))))
            menu.addItem(contextMenuItem("menu.image.saveAs", action: #selector(saveEditsAs(_:))))
            menu.addItem(contextMenuItem("menu.image.discardEdits", action: #selector(discardEdits(_:))))
        }

        menu.addItem(.separator())
        menu.addItem(contextMenuItem("menu.view.showInfo", action: #selector(toggleInspector(_:))))
        menu.addItem(contextMenuItem("menu.file.rename", action: #selector(renameCurrentImage(_:))))
        menu.addItem(.separator())
        menu.addItem(contextMenuItem("menu.file.moveToTrash", action: #selector(moveCurrentImageToTrash(_:))))
        return menu
    }

    func contextMenuItem(_ titleKey: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: AppStrings.text(titleKey), action: action, keyEquivalent: "")
        if let sourceItem = Self.menuItem(in: NSApp.mainMenu, matching: action) {
            item.keyEquivalent = sourceItem.keyEquivalent
            item.keyEquivalentModifierMask = sourceItem.keyEquivalentModifierMask
        }
        item.target = self
        item.isEnabled = validateMenuItem(item)
        return item
    }

    func makeFilmstripContextMenu(for item: ImageItem) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let isCurrent = viewModel.navigationState?.currentItem?.id == item.id
        menu.addItem(actionMenuItem(
            title: AppStrings.text("viewer.contextMenu.showImage"),
            isEnabled: !isCurrent
        ) { [weak self] in
            self?.selectImage(item)
        })
        menu.addItem(.separator())
        menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.copyPath")) { [weak self] in
            self?.copyPaths([item.url])
        })
        menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.reveal")) {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        })
        menu.addItem(.separator())
        menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.rename")) { [weak self] in
            self?.renameContextItem(item)
        })
        menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.moveToTrash")) { [weak self] in
            self?.trashContextItem(item)
        })
        return menu
    }

    func makeContinuousReadingContextMenu(for page: ContinuousReadingPage) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(actionMenuItem(title: AppStrings.text("viewer.contextMenu.showSingleImage")) { [weak self] in
            self?.showContinuousPageInSingleImageView(page.item)
        })
        menu.addItem(.separator())
        menu.addItem(actionMenuItem(
            title: AppStrings.text("menu.file.copyImage"),
            isEnabled: page.image != nil
        ) {
            guard let image = page.image else { return }
            _ = Self.writeImage(image.cgImage, to: .general)
        })
        menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.copyPath")) { [weak self] in
            self?.copyPaths([page.item.url])
        })
        menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.reveal")) {
            NSWorkspace.shared.activateFileViewerSelecting([page.item.url])
        })
        menu.addItem(.separator())
        menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.rename")) { [weak self] in
            self?.renameContextItem(page.item)
        })
        menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.moveToTrash")) { [weak self] in
            self?.trashContextItem(page.item)
        })
        return menu
    }

    func makeFolderBrowserContextMenu(for items: [ImageItem]) -> NSMenu? {
        guard !items.isEmpty, !folderBrowserViewModel.isOperating else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        if items.count == 1, let item = items.first {
            menu.addItem(actionMenuItem(title: AppStrings.text("folderBrowser.contextMenu.open")) { [weak self] in
                self?.openFolderBrowserItem(item)
            })
            menu.addItem(.separator())
            menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.copyPath")) { [weak self] in
                self?.copyPaths([item.url])
            })
            menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.reveal")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            })
            menu.addItem(.separator())
            menu.addItem(actionMenuItem(title: AppStrings.text("folderBrowser.contextMenu.move")) { [weak self] in
                self?.moveSelectedFolderBrowserItemsToFolder()
            })
            menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.rename")) { [weak self] in
                self?.renameSelectedFolderBrowserItems()
            })
            menu.addItem(.separator())
            menu.addItem(actionMenuItem(title: AppStrings.text("menu.file.moveToTrash")) { [weak self] in
                self?.moveSelectedFolderBrowserItemsToTrash()
            })
            return menu
        }

        let count = items.count
        menu.addItem(actionMenuItem(
            title: String(format: AppStrings.text("folderBrowser.contextMenu.copyPaths"), count)
        ) { [weak self] in
            self?.copyPaths(items.map(\.url))
        })
        menu.addItem(actionMenuItem(
            title: String(format: AppStrings.text("folderBrowser.contextMenu.revealItems"), count)
        ) {
            NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
        })
        menu.addItem(.separator())
        menu.addItem(actionMenuItem(
            title: String(format: AppStrings.text("folderBrowser.contextMenu.moveItems"), count)
        ) { [weak self] in
            self?.moveSelectedFolderBrowserItemsToFolder()
        })
        menu.addItem(actionMenuItem(
            title: String(format: AppStrings.text("folderBrowser.contextMenu.renameItems"), count)
        ) { [weak self] in
            self?.renameSelectedFolderBrowserItems()
        })
        menu.addItem(.separator())
        menu.addItem(actionMenuItem(
            title: String(format: AppStrings.text("folderBrowser.contextMenu.trashItems"), count)
        ) { [weak self] in
            self?.moveSelectedFolderBrowserItemsToTrash()
        })
        return menu
    }

    func actionMenuItem(
        title: String,
        isEnabled: Bool = true,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let dispatcher = ContextMenuActionDispatcher(handler: handler)
        let item = NSMenuItem(
            title: title,
            action: #selector(ContextMenuActionDispatcher.perform(_:)),
            keyEquivalent: ""
        )
        item.target = dispatcher
        item.representedObject = dispatcher
        item.isEnabled = isEnabled
        return item
    }

    func showContinuousPageInSingleImageView(_ item: ImageItem) {
        performWithCurrentItem(item) { [weak self] in
            self?.settings.usesContinuousReading = false
        }
    }

    static func menuCommand(for action: Selector?) -> MenuCommand? {
        switch action {
        case #selector(renameCurrentImage(_:)),
             #selector(revealCurrentImageInFinder(_:)),
             #selector(copyCurrentImagePath(_:)),
             #selector(moveCurrentImageToTrash(_:)):
            return .fileOperationRequiringCurrentItem
        case #selector(copyCurrentImage(_:)):
            return .copyImage
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
        case .copyImage:
            return hasCurrentImage
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

    @objc func showMoreMenu(_ sender: NSButton) {
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

    static func menuItem(in menu: NSMenu?, matching action: Selector) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.action == action { return item }
            if let match = menuItem(in: item.submenu, matching: action) { return match }
        }
        return nil
    }

    static func moreMenuSymbol(for action: Selector) -> String? {
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

}

@MainActor
final class ContextMenuActionDispatcher: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func perform(_ sender: Any?) {
        handler()
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if imageOperationTask != nil { return false }
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

