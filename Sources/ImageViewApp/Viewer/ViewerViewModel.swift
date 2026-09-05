import AppKit
import Combine
import Foundation
import ImageViewCore

private struct VersionedLoadedImage: Sendable {
    let image: DecodedImage
    let version: CurrentFileVersion?
}

enum ImageLoadPhase: Equatable {
    case empty
    case loading
    case preview
    case full
    case failed
}

private enum ImageLoadEvent: Sendable {
    case preview(DecodedImage)
    case full(VersionedLoadedImage)
}

private struct TrashedFile {
    let originalURL: URL
    var trashedURL: URL
}

private struct TrashOperation {
    let navigationStateBefore: NavigationState
    let navigationStateAfter: NavigationState?
    var files: [TrashedFile]
}

private func detachedDecode(
    _ operation: @escaping @Sendable () throws -> DecodedImage
) async throws -> DecodedImage {
    try await ImageDecodeExecutor.shared.decode(operation)
}

private let rawFullImageDecodeExecutor = ImageDecodeExecutor(maxConcurrentDecodeCount: 1)

private func detachedRawFullDecode(
    _ operation: @escaping @Sendable () throws -> DecodedImage
) async throws -> DecodedImage {
    try await rawFullImageDecodeExecutor.decode(operation)
}

private func versionsDescribeSameContent(
    _ lhs: CurrentFileVersion?,
    _ rhs: CurrentFileVersion?
) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case let (lhs?, rhs?):
        return lhs.hasSameContentIdentity(as: rhs)
    default:
        return false
    }
}

@MainActor
final class ViewerViewModel: ObservableObject {
    var onSuccessfulOpen: ((URL) -> Void)?
    @Published private(set) var navigationState: NavigationState?
    @Published private(set) var currentImage: DecodedImage?
    @Published private(set) var currentMetadata: ImageMetadata?
    @Published private(set) var errorMessage: String?
    @Published private(set) var displayTitle = "ImageView"
    @Published private(set) var hasUnsavedEdits = false
    @Published private(set) var isProcessingImage = false
    @Published private(set) var loadPhase: ImageLoadPhase = .empty

    var canEditCurrentImage: Bool {
        !isProcessingImage && loadPhase == .full
            && currentImage != nil
            && navigationState?.currentItem?.format.isCameraRAW != true
    }

    var currentFilename: String {
        navigationState?.currentItem?.url.lastPathComponent ?? "ImageView"
    }

    private let scanContainingDirectory: @Sendable (URL) async throws -> [ImageItem]
    private let loadImageAtURL: @Sendable (URL, SupportedImageFormat) async throws -> VersionedLoadedImage
    private let loadFullResolutionAtURL: @Sendable (URL, SupportedImageFormat) async throws -> VersionedLoadedImage
    private let loadPreviewAtURL: @Sendable (URL, SupportedImageFormat) async throws -> DecodedImage
    private let shouldLoadPreviewAtURL: @Sendable (URL) -> Bool
    private let moveToTrashAtURL: @Sendable (URL) throws -> URL
    private let restoreFromTrashAtURL: @Sendable (URL, URL) throws -> Void
    private let currentFileVersionAtURL: @Sendable (URL) -> CurrentFileVersion?
    private let fullResolutionRequestDelay: Duration
    private var metadataTask: Task<Void, Never>?
    private var metadataGeneration: UInt64 = 0
    typealias EditImage = @Sendable ([EditOperation], DecodedImage) throws -> DecodedImage
    private let editImage: EditImage
    private static let editingExecutor = ImageDecodeExecutor(maxConcurrentDecodeCount: 1)
    private let fileActions = FileActions()
    private let cache: ImageCache
    private var displayRequestGeneration: UInt64 = 0
    private var cancelActiveProgressiveLoad: (@Sendable () -> Void)?
    private var displayTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var fullResolutionTask: Task<Void, Never>?
    private var fullResolutionRequestGeneration: UInt64 = 0
    private var pendingOperations: [EditOperation] = []
    private var redoOperations: [EditOperation] = []
    private var trashUndoOperation: TrashOperation?
    private var trashRedoOperation: TrashOperation?
    private var persistedCurrentImage: DecodedImage?
    private var displayedFileVersion: CurrentFileVersion?
    var pendingOperationCountForTesting: Int { pendingOperations.count }
    var redoOperationCountForTesting: Int { redoOperations.count }
    var canUndo: Bool { !isProcessingImage && (!pendingOperations.isEmpty || trashUndoOperation != nil) }
    var canRedo: Bool { !isProcessingImage && (!redoOperations.isEmpty || trashRedoOperation != nil) }
    var undoMenuTitle: String {
        if let operation = pendingOperations.last {
            return String(
                format: AppStrings.text("menu.edit.undoNamed"),
                Self.localizedName(for: operation)
            )
        }
        guard trashUndoOperation != nil else { return AppStrings.text("menu.edit.undo") }
        return String(
            format: AppStrings.text("menu.edit.undoNamed"),
            AppStrings.text("editing.operation.moveToTrash")
        )
    }
    var redoMenuTitle: String {
        if let operation = redoOperations.last {
            return String(
                format: AppStrings.text("menu.edit.redoNamed"),
                Self.localizedName(for: operation)
            )
        }
        guard trashRedoOperation != nil else { return AppStrings.text("menu.edit.redo") }
        return String(
            format: AppStrings.text("menu.edit.redoNamed"),
            AppStrings.text("editing.operation.moveToTrash")
        )
    }
    static let maximumEditHistoryCount = 20
    static let defaultFullResolutionRequestDelay: Duration = .milliseconds(200)
    var cacheIdentityForTesting: ObjectIdentifier { ObjectIdentifier(cache) }

    init(
        scanContainingDirectory: @escaping @Sendable (URL) async throws -> [ImageItem] = {
            let scanner = DirectoryScanner()
            return try await scanner.scan(containing: $0)
        },
        decodeImageAtURL: (@Sendable (URL, SupportedImageFormat) throws -> DecodedImage)? = nil,
        moveToTrashAtURL: @escaping @Sendable (URL) throws -> URL = {
            try FileActions().moveToTrash($0)
        },
        restoreFromTrashAtURL: @escaping @Sendable (URL, URL) throws -> Void = {
            try FileActions().restoreFromTrash($0, to: $1)
        },
        currentFileVersionAtURL: @escaping @Sendable (URL) -> CurrentFileVersion? = CurrentFileVersion.read(at:),
        loadImageAtURL: (@Sendable (URL, SupportedImageFormat) async throws -> DecodedImage)? = nil,
        loadPreviewAtURL: (@Sendable (URL, SupportedImageFormat) async throws -> DecodedImage)? = nil,
        shouldLoadPreviewAtURL: (@Sendable (URL) -> Bool)? = nil,
        fullResolutionRequestDelay: Duration = ViewerViewModel.defaultFullResolutionRequestDelay,
        cache: ImageCache = .shared,
        editImage: @escaping EditImage = { operations, image in
            let output = try ImageEditingService().apply(operations, to: image.cgImage)
            return DecodedImage(cgImage: output, pixelSize: CGSize(width: output.width, height: output.height), isAnimated: false)
        }
    ) {
        let resolvedDecodeImageAtURL: @Sendable (URL, SupportedImageFormat) throws -> DecodedImage =
            decodeImageAtURL ?? {
                let decoder = ImageDecodeService()
                return try decoder.decode(url: $0, format: $1, purpose: .full)
            }
        self.scanContainingDirectory = scanContainingDirectory
        self.moveToTrashAtURL = moveToTrashAtURL
        self.restoreFromTrashAtURL = restoreFromTrashAtURL
        self.currentFileVersionAtURL = currentFileVersionAtURL
        self.fullResolutionRequestDelay = fullResolutionRequestDelay
        self.cache = cache
        self.editImage = editImage
        self.shouldLoadPreviewAtURL = shouldLoadPreviewAtURL ?? { url in
            loadPreviewAtURL != nil || ImageDecodeService.requiresDownsampledPreview(url: url, maxPixelSize: 2_048)
        }
        if let loadPreviewAtURL {
            self.loadPreviewAtURL = loadPreviewAtURL
        } else {
            self.loadPreviewAtURL = { url, format in
                try await detachedDecode {
                    try ImageDecodeService().decode(
                        url: url,
                        format: format,
                        purpose: .preview(maxPixelSize: 2_048)
                    )
                }
            }
        }
        let directFullResolutionLoader: @Sendable (URL, SupportedImageFormat) async throws -> VersionedLoadedImage = { url, format in
            for attempt in 0..<2 {
                guard let beforeVersion = currentFileVersionAtURL(url) else {
                    throw ImageDecodeError.cannotCreateSource
                }
                do {
                    let decoded = try await detachedRawFullDecode {
                        try resolvedDecodeImageAtURL(url, format)
                    }
                    try Task.checkCancellation()
                    guard let afterVersion = currentFileVersionAtURL(url),
                          afterVersion.hasSameContentIdentity(as: beforeVersion) else {
                        throw ImageDecodeError.cannotDecodeImage
                    }
                    return VersionedLoadedImage(image: decoded, version: afterVersion)
                } catch {
                    try Task.checkCancellation()
                    if attempt == 0,
                       let latestVersion = currentFileVersionAtURL(url),
                       !latestVersion.hasSameContentIdentity(as: beforeVersion) {
                        continue
                    }
                    throw error
                }
            }
            throw ImageDecodeError.cannotDecodeImage
        }
        if let loadImageAtURL {
            let versionedLoader: @Sendable (URL, SupportedImageFormat) async throws -> VersionedLoadedImage = { url, format in
                let image = try await loadImageAtURL(url, format)
                return VersionedLoadedImage(image: image, version: currentFileVersionAtURL(url))
            }
            self.loadImageAtURL = versionedLoader
            self.loadFullResolutionAtURL = versionedLoader
        } else if let decodeImageAtURL {
            self.loadImageAtURL = { url, format in
                let image = try await detachedDecode {
                    try decodeImageAtURL(url, format)
                }
                return VersionedLoadedImage(image: image, version: currentFileVersionAtURL(url))
            }
            self.loadFullResolutionAtURL = directFullResolutionLoader
        } else {
            let cache = cache
            self.loadImageAtURL = { url, format in
                for attempt in 0..<2 {
                    try Task.checkCancellation()
                    guard let beforeVersion = currentFileVersionAtURL(url) else {
                        throw ImageDecodeError.cannotCreateSource
                    }
                    do {
                        let decoded = try await cache.loadImage(for: url, matching: beforeVersion, priority: Task.currentPriority) { priority in
                            let decoded = try await ImageDecodeExecutor.shared.decode(priority: priority) {
                                try resolvedDecodeImageAtURL(url, format)
                            }
                            guard let afterVersion = currentFileVersionAtURL(url),
                                  afterVersion.hasSameContentIdentity(as: beforeVersion) else {
                                throw ImageDecodeError.cannotDecodeImage
                            }
                            return decoded
                        }
                        guard let completedVersion = currentFileVersionAtURL(url),
                              completedVersion.hasSameContentIdentity(as: beforeVersion) else {
                            throw ImageDecodeError.cannotDecodeImage
                        }
                        if completedVersion != beforeVersion {
                            await cache.insert(decoded, for: url, version: completedVersion)
                        }
                        return VersionedLoadedImage(image: decoded, version: completedVersion)
                    } catch {
                        try Task.checkCancellation()
                        if attempt == 0,
                           let currentVersion = currentFileVersionAtURL(url),
                           !currentVersion.hasSameContentIdentity(as: beforeVersion) {
                            continue
                        }
                        throw error
                    }
                }

                throw ImageDecodeError.cannotDecodeImage
            }
            self.loadFullResolutionAtURL = directFullResolutionLoader
        }
    }

    deinit {
        metadataTask?.cancel()
        displayTask?.cancel()
        preloadTask?.cancel()
        fullResolutionTask?.cancel()
        cancelActiveProgressiveLoad?()
    }

    func resetToEmptyState() {
        _ = beginDisplayRequest()
        clearEditHistory()
        navigationState = nil
        currentImage = nil
        currentMetadata = nil
        persistedCurrentImage = nil
        displayedFileVersion = nil
        hasUnsavedEdits = false
        errorMessage = nil
        loadPhase = .empty
        updateDisplayTitle()
    }

    func open(url: URL) async {
        let generation = beginDisplayRequest()
        clearEditHistory()
        persistedCurrentImage = nil
        displayedFileVersion = nil
        currentMetadata = nil
        hasUnsavedEdits = false
        loadPhase = .loading
        errorMessage = nil
        updateDisplayTitle()

        guard let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
            guard generation == displayRequestGeneration else { return }
            navigationState = nil
            currentImage = nil
            currentMetadata = nil
            persistedCurrentImage = nil
            loadPhase = .failed
            errorMessage = String(format: AppStrings.text("viewer.error.unsupportedFormat"), url.pathExtension)
            updateDisplayTitle()
            return
        }

        let fallbackItem = ImageItem(url: url, format: format)

        do {
            if format.isCameraRAW {
                let initialLoadTask = Task { [weak self] in
                    guard let self else { throw CancellationError() }
                    return try await self.display(url: url, format: format)
                }
                let cancelInitialLoad: @Sendable () -> Void = {
                    initialLoadTask.cancel()
                }
                cancelActiveProgressiveLoad = cancelInitialLoad
                defer {
                    cancelInitialLoad()
                    if generation == displayRequestGeneration {
                        cancelActiveProgressiveLoad = nil
                    }
                }

                let loaded = try await initialLoadTask.value
                guard generation == displayRequestGeneration else { return }
                currentImage = loaded.image
                persistedCurrentImage = loaded.image
                displayedFileVersion = loaded.version
                updateMetadata(url: url, format: format, image: loaded.image)
                navigationState = NavigationState(items: [fallbackItem], currentURL: url)
                loadPhase = .full
                updateDisplayTitle()
            } else {
                let loadPreviewAtURL = self.loadPreviewAtURL
                let loadImageAtURL = self.loadImageAtURL
                let (events, continuation) = AsyncThrowingStream<ImageLoadEvent, Error>.makeStream()
                let previewTask: Task<Void, Never>? = if shouldLoadPreviewAtURL(url) {
                    Task {
                        do {
                            let image = try await loadPreviewAtURL(url, format)
                            try Task.checkCancellation()
                            continuation.yield(.preview(image))
                        } catch {
                            // Preview failures are non-fatal; the full image still decides the open result.
                        }
                    }
                } else {
                    nil
                }
                let fullTask = Task {
                    do {
                        let image = try await loadImageAtURL(url, format)
                        try Task.checkCancellation()
                        continuation.yield(.full(image))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                let cancelProgressiveLoad: @Sendable () -> Void = {
                    previewTask?.cancel()
                    fullTask.cancel()
                    continuation.finish()
                }
                cancelActiveProgressiveLoad = cancelProgressiveLoad
                defer {
                    cancelProgressiveLoad()
                    if generation == displayRequestGeneration {
                        cancelActiveProgressiveLoad = nil
                    }
                }

                eventLoop: for try await event in events {
                    guard generation == displayRequestGeneration else { break }

                    switch event {
                    case let .preview(image):
                        guard loadPhase != .full else { continue }
                        currentImage = image
                        loadPhase = .preview
                    case let .full(loaded):
                        currentImage = loaded.image
                        persistedCurrentImage = loaded.image
                        displayedFileVersion = loaded.version
                        updateMetadata(url: url, format: format, image: loaded.image)
                        navigationState = NavigationState(items: [fallbackItem], currentURL: url)
                        loadPhase = .full
                        updateDisplayTitle()
                        cancelProgressiveLoad()
                        break eventLoop
                    }
                }
            }

            guard generation == displayRequestGeneration, loadPhase == .full else { return }

            if let items = try? await scanContainingDirectory(url) {
                guard generation == displayRequestGeneration else { return }
                let scannedNavigationState = NavigationState(items: items, currentURL: url)
                if let scannedItem = scannedNavigationState.currentItem {
                    if scannedItem.url.standardizedFileURL != url.standardizedFileURL {
                        let loaded = try await display(url: scannedItem.url, format: scannedItem.format)
                        guard generation == displayRequestGeneration else { return }
                        currentImage = loaded.image
                        persistedCurrentImage = loaded.image
                        displayedFileVersion = loaded.version
                        updateMetadata(url: scannedItem.url, format: scannedItem.format, image: loaded.image)
                    }
                    navigationState = scannedNavigationState
                    updateDisplayTitle()
                }
            }

            guard generation == displayRequestGeneration else { return }
            preloadNeighbors()
            onSuccessfulOpen?(url)
        } catch {
            guard generation == displayRequestGeneration else { return }
            navigationState = nil
            currentImage = nil
            currentMetadata = nil
            persistedCurrentImage = nil
            displayedFileVersion = nil
            loadPhase = .failed
            errorMessage = String(format: AppStrings.text("viewer.error.decode"), url.lastPathComponent)
            updateDisplayTitle()
        }
    }

    func showNext() {
        let previousURL = navigationState?.currentItem?.url
        navigationState?.moveNext()
        if navigationState?.currentItem?.url != previousURL {
            loadPhase = .loading
        }
        updateDisplayTitle()
        startDisplayCurrentAndPreload()
    }

    func showPrevious() {
        let previousURL = navigationState?.currentItem?.url
        navigationState?.movePrevious()
        if navigationState?.currentItem?.url != previousURL {
            loadPhase = .loading
        }
        updateDisplayTitle()
        startDisplayCurrentAndPreload()
    }

    func show(item: ImageItem) {
        guard let state = navigationState,
              state.items.contains(item) else {
            Task { await open(url: item.url) }
            return
        }

        navigationState = NavigationState(items: state.items, currentURL: item.url)
        if state.currentItem?.url != navigationState?.currentItem?.url {
            loadPhase = .loading
        }
        updateDisplayTitle()
        startDisplayCurrentAndPreload()
    }

    func moveCurrentToTrash() {
        guard let navigationStateBefore = navigationState,
              let item = navigationStateBefore.currentItem else { return }
        do {
            let files = try moveFilesToTrash(originalURLs: physicalFileURLs(for: item))
            navigationState?.removeCurrent()
            let navigationStateAfter = navigationState?.currentItem == nil ? nil : navigationState
            trashUndoOperation = TrashOperation(
                navigationStateBefore: navigationStateBefore,
                navigationStateAfter: navigationStateAfter,
                files: files
            )
            trashRedoOperation = nil
            if navigationState?.currentItem == nil {
                navigationState = nil
                currentImage = nil
                currentMetadata = nil
                persistedCurrentImage = nil
                displayedFileVersion = nil
                loadPhase = .empty
                errorMessage = nil
                updateDisplayTitle()
                return
            }

            loadPhase = .loading
            errorMessage = nil
            updateDisplayTitle()
            startDisplayCurrentAndPreload()
        } catch {
            errorMessage = String(format: AppStrings.text("viewer.error.trash"), item.displayFilename)
        }
    }

    func renameCurrent(to newBaseName: String) {
        guard let item = navigationState?.currentItem else { return }
        do {
            let newURL = try fileActions.rename(item.url, to: newBaseName)
            navigationState?.replaceCurrentURL(newURL, format: item.format)
            displayedFileVersion = currentFileVersionAtURL(newURL)
            if let image = currentImage {
                updateMetadata(url: newURL, format: item.format, image: image)
            }
            errorMessage = nil
            updateDisplayTitle()
        } catch {
            errorMessage = String(format: AppStrings.text("viewer.error.rename"), item.url.lastPathComponent)
        }
    }

    func applyItemURLMigrations(_ migrations: [URL: URL]) {
        let standardizedMigrations = Dictionary(
            uniqueKeysWithValues: migrations.map { ($0.key.standardizedFileURL, $0.value.standardizedFileURL) }
        )
        let previousCurrentURL = navigationState?.currentItem?.url.standardizedFileURL
        navigationState?.applyURLMigrations(standardizedMigrations)
        guard let previousCurrentURL,
              let newCurrentItem = navigationState?.currentItem,
              newCurrentItem.url.standardizedFileURL != previousCurrentURL else {
            return
        }
        if loadPhase == .full,
           let image = currentImage,
           persistedCurrentImage != nil {
            displayedFileVersion = currentFileVersionAtURL(newCurrentItem.url)
            updateMetadata(url: newCurrentItem.url, format: newCurrentItem.format, image: image)
            updateDisplayTitle()
            return
        }

        currentImage = nil
        currentMetadata = nil
        persistedCurrentImage = nil
        displayedFileVersion = nil
        errorMessage = nil
        updateDisplayTitle()
        startDisplayCurrentAndPreload()
    }

    @discardableResult
    func removeItemsFromNavigation(_ removedURLs: Set<URL>) -> URL? {
        let standardizedURLs = Set(removedURLs.map(\.standardizedFileURL))
        let previousCurrentURL = navigationState?.currentItem?.url.standardizedFileURL
        navigationState?.removeItems(withURLs: standardizedURLs)
        let replacementURL = navigationState?.currentItem?.url.standardizedFileURL
        guard replacementURL != previousCurrentURL else { return replacementURL }

        _ = beginDisplayRequest()
        clearEditHistory()
        hasUnsavedEdits = false

        guard navigationState?.currentItem != nil else {
            currentImage = nil
            currentMetadata = nil
            persistedCurrentImage = nil
            displayedFileVersion = nil
            loadPhase = .empty
            errorMessage = nil
            updateDisplayTitle()
            return nil
        }
        loadPhase = .loading
        errorMessage = nil
        updateDisplayTitle()
        startDisplayCurrentAndPreload()
        return replacementURL
    }

    func revealCurrentInFinder() {
        guard let url = navigationState?.currentItem?.url else { return }
        fileActions.revealInFinder(url)
    }

    func applyEdit(_ operation: EditOperation) async {
        guard canEditCurrentImage, let image = currentImage else { return }
        guard pendingOperations.count < Self.maximumEditHistoryCount else {
            errorMessage = AppStrings.text("editing.history.limitReached")
            return
        }

        isProcessingImage = true
        defer { isProcessingImage = false }
        let generation = displayRequestGeneration
        do {
            let editImage = self.editImage
            let output = try await Self.editingExecutor.decode { try editImage([operation], image) }
            guard generation == displayRequestGeneration, !Task.isCancelled else { return }
            currentImage = output
            if let item = navigationState?.currentItem, let currentImage {
                updateMetadata(url: item.url, format: item.format, image: currentImage)
            }
            pendingOperations.append(operation)
            redoOperations.removeAll()
            trashRedoOperation = nil
            hasUnsavedEdits = true
            errorMessage = nil
            updateDisplayTitle()
        } catch {
            guard generation == displayRequestGeneration else { return }
            errorMessage = AppStrings.text("viewer.error.edit")
        }
    }

    @discardableResult
    func undoEdit() async -> Bool {
        guard !isProcessingImage else { return false }
        if let operation = pendingOperations.last {
            let remaining = Array(pendingOperations.dropLast())
            guard await rebuildEditedImageFromHistory(remaining) else { return false }
            pendingOperations = remaining
            redoOperations.append(operation)
            return true
        }
        guard var operation = trashUndoOperation else { return false }
        do {
            try restoreFilesFromTrash(&operation.files)
            trashUndoOperation = nil
            trashRedoOperation = operation
            displayNavigationState(operation.navigationStateBefore)
            return true
        } catch {
            errorMessage = AppStrings.text("fileOperation.restoreFromTrashFailed")
            return false
        }
    }

    @discardableResult
    func redoEdit() async -> Bool {
        guard !isProcessingImage else { return false }
        if let operation = redoOperations.last {
            let updated = pendingOperations + [operation]
            guard await rebuildEditedImageFromHistory(updated) else { return false }
            pendingOperations = updated
            redoOperations.removeLast()
            return true
        }
        guard var operation = trashRedoOperation else { return false }
        do {
            operation.files = try moveFilesToTrash(
                originalURLs: operation.files.map(\.originalURL)
            )
            trashRedoOperation = nil
            trashUndoOperation = operation
            displayNavigationState(operation.navigationStateAfter)
            return true
        } catch {
            errorMessage = AppStrings.text("fileOperation.moveToTrashFailed")
            return false
        }
    }

    @discardableResult
    func saveCurrentEdits() async -> Bool {
        guard let item = navigationState?.currentItem else { return false }
        return await saveCurrentEdits(to: item.url, format: item.format)
    }

    @discardableResult
    func saveCurrentEdits(to targetURL: URL, format: SupportedImageFormat) async -> Bool {
        guard canEditCurrentImage,
              let item = navigationState?.currentItem,
              let image = currentImage else { return false }
        isProcessingImage = true
        defer { isProcessingImage = false }
        let generation = displayRequestGeneration
        do {
            // Saving is allowed to finish atomically once started. UI transitions wait
            // for this result; the generation guard also protects programmatic opens.
            let decoded = try await Self.editingExecutor.decode {
                try ImageEditingService().save(image.cgImage, to: targetURL, format: format, metadataSourceURL: item.url)
                return DecodedImage(cgImage: image.cgImage, pixelSize: image.pixelSize, isAnimated: false)
            }
            guard let writtenVersion = currentFileVersionAtURL(targetURL) else {
                throw ImageDecodeError.cannotCreateSource
            }
            await cache.insert(decoded, for: targetURL, version: writtenVersion)
            guard generation == displayRequestGeneration else { return false }
            navigationState?.replaceCurrentURL(targetURL, format: format)
            currentImage = decoded
            persistedCurrentImage = decoded
            displayedFileVersion = writtenVersion
            updateMetadata(url: targetURL, format: format, image: decoded)
            clearEditHistory()
            hasUnsavedEdits = false
            errorMessage = nil
            updateDisplayTitle()
            return true
        } catch {
            guard generation == displayRequestGeneration else { return false }
            errorMessage = AppStrings.text("viewer.error.save")
            return false
        }
    }

    @discardableResult
    func discardCurrentEdits() -> Bool {
        guard !isProcessingImage else { return false }
        guard hasUnsavedEdits else {
            errorMessage = nil
            return true
        }

        do {
            let restoredImage = try restoredCurrentImage()
            currentImage = restoredImage
            persistedCurrentImage = restoredImage
            if let item = navigationState?.currentItem {
                updateMetadata(url: item.url, format: item.format, image: restoredImage)
            }
            clearEditHistory()
            hasUnsavedEdits = false
            errorMessage = nil
            updateDisplayTitle()
            return true
        } catch {
            errorMessage = AppStrings.text("viewer.error.restore")
            return false
        }
    }

    func discardCurrentEditsAndReload() {
        guard discardCurrentEdits() else { return }
        startDisplayCurrentAndPreload()
    }

    func copyCurrentPathToPasteboard() {
        guard let url = navigationState?.currentItem?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileActions.absolutePath(for: url), forType: .string)
    }

    func requestCurrentFullResolutionIfNeeded() {
        guard fullResolutionTask == nil,
              loadPhase == .full,
              let item = navigationState?.currentItem,
              item.format.isCameraRAW,
              let currentImage,
              !currentImage.isFullResolution else {
            return
        }

        let generation = displayRequestGeneration
        fullResolutionRequestGeneration &+= 1
        let fullResolutionGeneration = fullResolutionRequestGeneration
        let expectedURL = item.url.standardizedFileURL
        let expectedVersion = displayedFileVersion
        let loadFullResolutionAtURL = self.loadFullResolutionAtURL
        let currentFileVersionAtURL = self.currentFileVersionAtURL
        let requestDelay = fullResolutionRequestDelay

        fullResolutionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: requestDelay)
                try Task.checkCancellation()
                let loaded = try await loadFullResolutionAtURL(item.url, item.format)
                try Task.checkCancellation()
                let latestVersion = currentFileVersionAtURL(item.url)

                guard let self,
                      generation == self.displayRequestGeneration,
                      fullResolutionGeneration == self.fullResolutionRequestGeneration,
                      self.navigationState?.currentItem?.url.standardizedFileURL == expectedURL,
                      versionsDescribeSameContent(expectedVersion, loaded.version),
                      versionsDescribeSameContent(loaded.version, latestVersion),
                      loaded.image.isFullResolution else {
                    if let self,
                       generation == self.displayRequestGeneration,
                       fullResolutionGeneration == self.fullResolutionRequestGeneration {
                        self.fullResolutionTask = nil
                    }
                    return
                }

                self.currentImage = loaded.image
                self.persistedCurrentImage = loaded.image
                self.displayedFileVersion = loaded.version
                self.updateMetadata(url: item.url, format: item.format, image: loaded.image)
                self.fullResolutionTask = nil
            } catch {
                guard let self,
                      generation == self.displayRequestGeneration,
                      fullResolutionGeneration == self.fullResolutionRequestGeneration else { return }
                self.fullResolutionTask = nil
            }
        }
    }

    func cancelCurrentFullResolutionRequest() {
        fullResolutionRequestGeneration &+= 1
        fullResolutionTask?.cancel()
        fullResolutionTask = nil
    }

    func continuousReadingPages(
        centeredAt focusedItemID: ImageItem.ID? = nil,
        radius: Int = ContinuousReadingView.preloadRadius
    ) async -> [ContinuousReadingPage] {
        guard let state = navigationState,
              let current = state.currentItem,
              let currentIndex = state.currentIndex else { return [] }
        let generation = displayRequestGeneration
        let focusedIndex = focusedItemID.flatMap { id in
            state.items.firstIndex { $0.id == id }
        } ?? currentIndex
        let boundedRadius = min(max(0, radius), ContinuousReadingView.preloadRadius)
        let lowerBound = max(0, focusedIndex - boundedRadius)
        let upperBound = min(state.items.count - 1, focusedIndex + boundedRadius)
        var decodedByID: [ImageItem.ID: DecodedImage] = [:]
        var decodedByteCost = 0
        let decodeOrder = Array(lowerBound...upperBound).sorted {
            let leftDistance = abs($0 - focusedIndex)
            let rightDistance = abs($1 - focusedIndex)
            return leftDistance == rightDistance ? $0 < $1 : leftDistance < rightDistance
        }

        for index in decodeOrder {
            let item = state.items[index]
            guard !Task.isCancelled, generation == displayRequestGeneration, navigationState?.currentItem?.id == current.id else { return [] }
            let image: DecodedImage?
            if item.id == current.id, let currentImage {
                image = currentImage
            } else if item.format.isCameraRAW {
                image = try? await loadPreviewAtURL(item.url, item.format)
            } else {
                image = try? await display(url: item.url, format: item.format).image
            }
            guard !Task.isCancelled, generation == displayRequestGeneration, navigationState?.currentItem?.id == current.id else { return [] }
            guard let image else { continue }
            let (nextCost, overflow) = decodedByteCost.addingReportingOverflow(image.decodedByteCost)
            let fitsBudget = !overflow && nextCost <= ContinuousReadingView.maximumDecodedByteCost
            if fitsBudget || decodedByID.isEmpty {
                decodedByID[item.id] = image
                decodedByteCost = overflow ? Int.max : nextCost
            }
        }
        return state.items.map {
            ContinuousReadingPage(item: $0, image: decodedByID[$0.id])
        }
    }

    func refreshCurrentFileIfNeeded() async {
        guard !isProcessingImage else { return }
        guard let item = navigationState?.currentItem else { return }
        guard let currentVersion = currentFileVersionAtURL(item.url) else {
            removeExternallyUnavailableCurrentItem(item)
            return
        }
        guard currentVersion != displayedFileVersion else { return }
        guard !hasUnsavedEdits else {
            errorMessage = String(format: AppStrings.text("viewer.error.externalChange"), item.url.lastPathComponent)
            return
        }

        let generation = beginDisplayRequest()
        loadPhase = .loading
        await cache.removeImage(for: item.url)
        guard generation == displayRequestGeneration else { return }
        do {
            let loaded = try await display(url: item.url, format: item.format)
            guard generation == displayRequestGeneration,
                  navigationState?.currentItem?.url.standardizedFileURL == item.url.standardizedFileURL else { return }
            currentImage = loaded.image
            persistedCurrentImage = loaded.image
            displayedFileVersion = loaded.version
            updateMetadata(url: item.url, format: item.format, image: loaded.image)
            loadPhase = .full
            errorMessage = nil
            preloadNeighbors()
        } catch {
            guard generation == displayRequestGeneration else { return }
            loadPhase = .failed
            errorMessage = String(format: AppStrings.text("viewer.error.externalDecode"), item.url.lastPathComponent)
        }
    }

    private func displayCurrentAndPreload(item: ImageItem, generation: UInt64) async {
        do {
            let loaded = try await display(url: item.url, format: item.format)
            guard generation == displayRequestGeneration,
                  navigationState?.currentItem?.url == item.url else {
                return
            }
            currentImage = loaded.image
            persistedCurrentImage = loaded.image
            displayedFileVersion = loaded.version
            updateMetadata(url: item.url, format: item.format, image: loaded.image)
            loadPhase = .full
            preloadNeighbors()
        } catch {
            guard generation == displayRequestGeneration,
                  navigationState?.currentItem?.url == item.url else {
                return
            }
            currentImage = nil
            currentMetadata = nil
            persistedCurrentImage = nil
            displayedFileVersion = nil
            loadPhase = .failed
            errorMessage = String(format: AppStrings.text("viewer.error.decode"), item.url.lastPathComponent)
            updateDisplayTitle()
        }
    }

    private func clearEditHistory() {
        pendingOperations.removeAll()
        redoOperations.removeAll()
    }

    private func physicalFileURLs(for item: ImageItem) -> [URL] {
        var urls = [item.url]
        if let pairedRawURL = item.pairedRawURL,
           pairedRawURL.standardizedFileURL != item.url.standardizedFileURL {
            urls.append(pairedRawURL)
        }
        return urls
    }

    private func moveFilesToTrash(originalURLs: [URL]) throws -> [TrashedFile] {
        var movedFiles: [TrashedFile] = []
        do {
            for originalURL in originalURLs {
                movedFiles.append(
                    TrashedFile(
                        originalURL: originalURL,
                        trashedURL: try moveToTrashAtURL(originalURL)
                    )
                )
            }
            return movedFiles
        } catch {
            for file in movedFiles.reversed() {
                try? restoreFromTrashAtURL(file.trashedURL, file.originalURL)
            }
            throw error
        }
    }

    private func restoreFilesFromTrash(_ files: inout [TrashedFile]) throws {
        var restoredIndices: [Int] = []
        do {
            for index in files.indices {
                try restoreFromTrashAtURL(files[index].trashedURL, files[index].originalURL)
                restoredIndices.append(index)
            }
        } catch {
            for index in restoredIndices.reversed() {
                if let trashedURL = try? moveToTrashAtURL(files[index].originalURL) {
                    files[index].trashedURL = trashedURL
                }
            }
            throw error
        }
    }

    private func displayNavigationState(_ state: NavigationState?) {
        _ = beginDisplayRequest()
        clearEditHistory()
        navigationState = state
        hasUnsavedEdits = false
        errorMessage = nil
        guard state?.currentItem != nil else {
            currentImage = nil
            currentMetadata = nil
            persistedCurrentImage = nil
            displayedFileVersion = nil
            loadPhase = .empty
            updateDisplayTitle()
            return
        }
        loadPhase = .loading
        updateDisplayTitle()
        startDisplayCurrentAndPreload()
    }

    private static func localizedName(for operation: EditOperation) -> String {
        let key: String
        switch operation {
        case .rotateClockwise: key = "editing.operation.rotateClockwise"
        case .rotateCounterClockwise: key = "editing.operation.rotateCounterClockwise"
        case .mirrorHorizontal: key = "editing.operation.mirrorHorizontal"
        case .mirrorVertical: key = "editing.operation.mirrorVertical"
        case .crop: key = "editing.operation.crop"
        }
        return AppStrings.text(key)
    }

    private func rebuildEditedImageFromHistory(_ operations: [EditOperation]) async -> Bool {
        guard let baseline = persistedCurrentImage else { return false }
        isProcessingImage = true
        defer { isProcessingImage = false }
        let generation = displayRequestGeneration
        do {
            let editImage = self.editImage
            let rebuilt = try await Self.editingExecutor.decode { try editImage(operations, baseline) }
            guard generation == displayRequestGeneration, !Task.isCancelled else { return false }
            currentImage = rebuilt
            if let item = navigationState?.currentItem {
                updateMetadata(url: item.url, format: item.format, image: rebuilt)
            }
            hasUnsavedEdits = !operations.isEmpty
            errorMessage = nil
            updateDisplayTitle()
            return true
        } catch {
            guard generation == displayRequestGeneration else { return false }
            errorMessage = AppStrings.text("editing.history.rebuildFailed")
            return false
        }
    }

    private func display(url: URL, format: SupportedImageFormat) async throws -> VersionedLoadedImage {
        guard format.isCameraRAW else {
            return try await loadImageAtURL(url, format)
        }

        for _ in 0..<2 {
            let beforeVersion = currentFileVersionAtURL(url)
            do {
                let image = try await loadPreviewAtURL(url, format)
                try Task.checkCancellation()
                let afterVersion = currentFileVersionAtURL(url)
                if versionsDescribeSameContent(beforeVersion, afterVersion) {
                    return VersionedLoadedImage(image: image, version: afterVersion)
                }
            } catch {
                try Task.checkCancellation()
                break
            }
        }
        try Task.checkCancellation()
        return try await loadFullResolutionAtURL(url, format)
    }

    private func removeExternallyUnavailableCurrentItem(_ item: ImageItem) {
        navigationState?.removeCurrent()
        displayedFileVersion = nil
        errorMessage = String(format: AppStrings.text("viewer.error.externalRemoval"), item.url.lastPathComponent)

        guard navigationState?.currentItem != nil else {
            navigationState = nil
            currentImage = nil
            currentMetadata = nil
            persistedCurrentImage = nil
            loadPhase = .empty
            updateDisplayTitle()
            return
        }

        loadPhase = .loading
        updateDisplayTitle()
        startDisplayCurrentAndPreload()
    }

    private func startDisplayCurrentAndPreload() {
        guard let item = navigationState?.currentItem else { return }
        clearEditHistory()
        hasUnsavedEdits = false
        let generation = beginDisplayRequest()
        loadPhase = .loading
        displayTask = Task { [weak self] in
            await self?.displayCurrentAndPreload(item: item, generation: generation)
        }
    }

    private func beginDisplayRequest() -> UInt64 {
        cancelActiveProgressiveLoad?()
        cancelActiveProgressiveLoad = nil
        displayTask?.cancel()
        displayTask = nil
        preloadTask?.cancel()
        preloadTask = nil
        fullResolutionRequestGeneration &+= 1
        fullResolutionTask?.cancel()
        fullResolutionTask = nil
        displayRequestGeneration &+= 1
        return displayRequestGeneration
    }

    private func preloadNeighbors() {
        guard let state = navigationState, let current = state.currentItem else { return }
        let currentIndex = state.currentIndex ?? 0
        let lowerBound = max(0, currentIndex - 2)
        let upperBound = min(state.items.count - 1, currentIndex + 2)
        let neighbors = state.items[lowerBound...upperBound].filter {
            $0.id != current.id && Self.canPreloadInBackground($0.format)
        }

        guard !neighbors.isEmpty else { return }
        preloadTask?.cancel()
        let loadImageAtURL = self.loadImageAtURL
        preloadTask = Task.detached(priority: .utility) {
            for item in neighbors {
                guard !Task.isCancelled else { return }
                _ = try? await loadImageAtURL(item.url, item.format)
            }
        }
    }

    static func canPreloadInBackground(_ format: SupportedImageFormat) -> Bool {
        switch format {
        case .gif, .svg, .webp, .avif, .arw, .nef:
            return false
        case .jpeg, .png, .tiff, .bmp, .heic, .heif:
            return true
        }
    }

    private func updateDisplayTitle() {
        let filename = navigationState?.currentItem?.displayFilename ?? "ImageView"
        displayTitle = Self.displayTitle(filename: filename, hasUnsavedEdits: hasUnsavedEdits)
    }

    static func displayTitle(filename: String, hasUnsavedEdits: Bool, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        hasUnsavedEdits ? String(format: AppStrings.text("viewer.title.edited", preferredLanguages: preferredLanguages), filename) : filename
    }

    private func updateMetadata(url: URL, format: SupportedImageFormat, image: DecodedImage) {
        let reportedPixelSize = if format.isCameraRAW {
            image.sourcePixelSize
        } else {
            CGSize(width: image.cgImage.width, height: image.cgImage.height)
        }
        metadataTask?.cancel()
        metadataGeneration &+= 1
        let generation = metadataGeneration
        let width = Int(reportedPixelSize.width.rounded())
        let height = Int(reportedPixelSize.height.rounded())
        if let metadata = currentMetadata, metadata.url == url, metadata.format == format {
            currentMetadata = metadata.replacingDimensions(width: width, height: height)
        } else {
            currentMetadata = ImageMetadata(url: url, format: format, pixelWidth: width, pixelHeight: height, fileSize: nil, modifiedAt: nil)
        }
        metadataTask = Task { [weak self] in
            guard let metadata = try? await ImageMetadataLoader.shared.metadata(for: url, format: format, width: width, height: height) else { return }
            guard !Task.isCancelled, let self, self.metadataGeneration == generation,
                  self.currentMetadata?.url == url else { return }
            self.currentMetadata = metadata
        }
    }

    private func restoredCurrentImage() throws -> DecodedImage {
        if let persistedCurrentImage {
            return persistedCurrentImage
        }

        throw ImageDecodeError.cannotDecodeImage
    }
}
