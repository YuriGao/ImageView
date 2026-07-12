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

private func detachedDecode(
    _ operation: @escaping @Sendable () throws -> DecodedImage
) async throws -> DecodedImage {
    let task = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        let image = try operation()
        try Task.checkCancellation()
        return image
    }

    return try await withTaskCancellationHandler {
        try Task.checkCancellation()
        let image = try await task.value
        try Task.checkCancellation()
        return image
    } onCancel: {
        task.cancel()
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
    @Published private(set) var loadPhase: ImageLoadPhase = .empty

    var canEditCurrentImage: Bool {
        loadPhase == .full && currentImage != nil
    }

    var currentFilename: String {
        navigationState?.currentItem?.url.lastPathComponent ?? "ImageView"
    }

    private let scanContainingDirectory: @Sendable (URL) async throws -> [ImageItem]
    private let decodeImageAtURL: @Sendable (URL, SupportedImageFormat) throws -> DecodedImage
    private let loadImageAtURL: @Sendable (URL, SupportedImageFormat) async throws -> VersionedLoadedImage
    private let loadPreviewAtURL: @Sendable (URL, SupportedImageFormat) async throws -> DecodedImage
    private let moveToTrashAtURL: @Sendable (URL) throws -> Void
    private let currentFileVersionAtURL: @Sendable (URL) -> CurrentFileVersion?
    private let metadataService = ImageMetadataService()
    private let fileActions = FileActions()
    private let editingService = ImageEditingService()
    private let cache = ImageCache(costLimit: ImageCache.defaultFullImageCostLimit)
    private var displayRequestGeneration: UInt64 = 0
    private var cancelActiveProgressiveLoad: (() -> Void)?
    private var pendingOperations: [EditOperation] = []
    private var persistedCurrentImage: DecodedImage?
    private var displayedFileVersion: CurrentFileVersion?

    init(
        scanContainingDirectory: @escaping @Sendable (URL) async throws -> [ImageItem] = {
            let scanner = DirectoryScanner()
            return try await scanner.scan(containing: $0)
        },
        decodeImageAtURL: (@Sendable (URL, SupportedImageFormat) throws -> DecodedImage)? = nil,
        moveToTrashAtURL: @escaping @Sendable (URL) throws -> Void = {
            try FileActions().moveToTrash($0)
        },
        currentFileVersionAtURL: @escaping @Sendable (URL) -> CurrentFileVersion? = CurrentFileVersion.read(at:),
        loadImageAtURL: (@Sendable (URL, SupportedImageFormat) async throws -> DecodedImage)? = nil,
        loadPreviewAtURL: (@Sendable (URL, SupportedImageFormat) async throws -> DecodedImage)? = nil
    ) {
        let resolvedDecodeImageAtURL: @Sendable (URL, SupportedImageFormat) throws -> DecodedImage =
            decodeImageAtURL ?? {
                let decoder = ImageDecodeService()
                return try decoder.decode(url: $0, format: $1, maxPixelSize: nil)
            }
        self.scanContainingDirectory = scanContainingDirectory
        self.decodeImageAtURL = resolvedDecodeImageAtURL
        self.moveToTrashAtURL = moveToTrashAtURL
        self.currentFileVersionAtURL = currentFileVersionAtURL
        if let loadPreviewAtURL {
            self.loadPreviewAtURL = loadPreviewAtURL
        } else {
            self.loadPreviewAtURL = { url, format in
                try await detachedDecode {
                    try ImageDecodeService().decode(url: url, format: format, maxPixelSize: 2_048)
                }
            }
        }
        if let loadImageAtURL {
            self.loadImageAtURL = { url, format in
                let image = try await loadImageAtURL(url, format)
                return VersionedLoadedImage(image: image, version: currentFileVersionAtURL(url))
            }
        } else if let decodeImageAtURL {
            self.loadImageAtURL = { url, format in
                let image = try await detachedDecode {
                    try decodeImageAtURL(url, format)
                }
                return VersionedLoadedImage(image: image, version: currentFileVersionAtURL(url))
            }
        } else {
            let cache = self.cache
            self.loadImageAtURL = { url, format in
                guard let liveVersion = currentFileVersionAtURL(url) else {
                    throw ImageDecodeError.cannotCreateSource
                }
                if let cached = await cache.image(for: url, matching: liveVersion) {
                    return VersionedLoadedImage(image: cached, version: liveVersion)
                }

                for attempt in 0..<2 {
                    guard let beforeVersion = currentFileVersionAtURL(url) else {
                        throw ImageDecodeError.cannotCreateSource
                    }
                    let decoded = try await detachedDecode {
                        try resolvedDecodeImageAtURL(url, format)
                    }
                    guard let afterVersion = currentFileVersionAtURL(url) else {
                        throw ImageDecodeError.cannotCreateSource
                    }
                    guard beforeVersion == afterVersion else {
                        if attempt == 0 { continue }
                        throw ImageDecodeError.cannotDecodeImage
                    }

                    await cache.insert(decoded, for: url, version: beforeVersion)
                    return VersionedLoadedImage(image: decoded, version: beforeVersion)
                }

                throw ImageDecodeError.cannotDecodeImage
            }
        }
    }

    func resetToEmptyState() {
        _ = beginDisplayRequest()
        pendingOperations.removeAll()
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
        pendingOperations.removeAll()
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
            errorMessage = "不支持的图片格式：\(url.pathExtension)"
            updateDisplayTitle()
            return
        }

        let fallbackItem = ImageItem(url: url, format: format)

        do {
            let loadPreviewAtURL = self.loadPreviewAtURL
            let loadImageAtURL = self.loadImageAtURL
            let (events, continuation) = AsyncThrowingStream<ImageLoadEvent, Error>.makeStream()
            let previewTask = Task {
                do {
                    let image = try await loadPreviewAtURL(url, format)
                    try Task.checkCancellation()
                    continuation.yield(.preview(image))
                } catch {
                    // Preview failures are non-fatal; the full image still decides the open result.
                }
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
            let cancelProgressiveLoad = {
                previewTask.cancel()
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

            guard generation == displayRequestGeneration, loadPhase == .full else { return }

            do {
                let items = try await scanContainingDirectory(url)
                guard generation == displayRequestGeneration else { return }

                if items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                    navigationState = NavigationState(items: items, currentURL: url)
                    updateDisplayTitle()
                }
            } catch {
                guard generation == displayRequestGeneration else { return }
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
            errorMessage = "图片损坏或无法解码：\(url.lastPathComponent)"
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
        guard let url = navigationState?.currentItem?.url else { return }
        do {
            try moveToTrashAtURL(url)
            navigationState?.removeCurrent()
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
            errorMessage = "无法移动到废纸篓：\(url.lastPathComponent)"
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
            errorMessage = "无法重命名：\(item.url.lastPathComponent)"
        }
    }

    func migrateDisplayedItemURL(from oldURL: URL, to newURL: URL) {
        guard let item = navigationState?.currentItem,
              item.url.standardizedFileURL == oldURL.standardizedFileURL else {
            return
        }
        navigationState?.replaceCurrentURL(newURL, format: item.format)
        displayedFileVersion = currentFileVersionAtURL(newURL)
        if let image = currentImage {
            updateMetadata(url: newURL, format: item.format, image: image)
        }
        updateDisplayTitle()
    }

    func revealCurrentInFinder() {
        guard let url = navigationState?.currentItem?.url else { return }
        fileActions.revealInFinder(url)
    }

    func applyEdit(_ operation: EditOperation) {
        guard canEditCurrentImage, let image = currentImage else { return }

        do {
            let output = try editingService.apply([operation], to: image.cgImage)
            currentImage = DecodedImage(
                cgImage: output,
                pixelSize: CGSize(width: output.width, height: output.height),
                isAnimated: false
            )
            if let item = navigationState?.currentItem, let currentImage {
                updateMetadata(url: item.url, format: item.format, image: currentImage)
            }
            pendingOperations.append(operation)
            hasUnsavedEdits = true
            errorMessage = nil
            updateDisplayTitle()
        } catch {
            errorMessage = "无法应用编辑"
        }
    }

    @discardableResult
    func saveCurrentEdits() -> Bool {
        guard canEditCurrentImage,
              let item = navigationState?.currentItem,
              let image = currentImage else {
            return false
        }

        do {
            try editingService.save(
                image.cgImage,
                to: item.url,
                format: item.format,
                metadataSourceURL: item.url
            )
            let decoded = DecodedImage(
                cgImage: image.cgImage,
                pixelSize: image.pixelSize,
                isAnimated: false
            )
            guard let writtenVersion = currentFileVersionAtURL(item.url) else {
                throw ImageDecodeError.cannotCreateSource
            }
            Task { [cache] in
                await cache.insert(decoded, for: item.url, version: writtenVersion)
            }
            persistedCurrentImage = decoded
            displayedFileVersion = writtenVersion
            updateMetadata(url: item.url, format: item.format, image: decoded)
            pendingOperations.removeAll()
            hasUnsavedEdits = false
            errorMessage = nil
            updateDisplayTitle()
            return true
        } catch {
            errorMessage = "无法保存该格式的编辑结果"
            return false
        }
    }

    @discardableResult
    func saveCurrentEdits(to targetURL: URL, format: SupportedImageFormat) -> Bool {
        guard canEditCurrentImage,
              let item = navigationState?.currentItem,
              let image = currentImage else {
            return false
        }

        do {
            try editingService.save(
                image.cgImage,
                to: targetURL,
                format: format,
                metadataSourceURL: item.url
            )
            let decoded = DecodedImage(cgImage: image.cgImage, pixelSize: image.pixelSize, isAnimated: false)
            guard let writtenVersion = currentFileVersionAtURL(targetURL) else {
                throw ImageDecodeError.cannotCreateSource
            }
            Task { [cache] in
                await cache.insert(decoded, for: targetURL, version: writtenVersion)
            }
            navigationState?.replaceCurrentURL(targetURL, format: format)
            persistedCurrentImage = decoded
            displayedFileVersion = writtenVersion
            updateMetadata(url: targetURL, format: format, image: decoded)
            pendingOperations.removeAll()
            hasUnsavedEdits = false
            errorMessage = nil
            updateDisplayTitle()
            return true
        } catch {
            errorMessage = "无法另存编辑结果"
            return false
        }
    }

    @discardableResult
    func discardCurrentEdits() -> Bool {
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
            pendingOperations.removeAll()
            hasUnsavedEdits = false
            errorMessage = nil
            updateDisplayTitle()
            return true
        } catch {
            errorMessage = "无法还原原始图片"
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

    func refreshCurrentFileIfNeeded() async {
        guard let item = navigationState?.currentItem else { return }
        guard let currentVersion = currentFileVersionAtURL(item.url) else {
            removeExternallyUnavailableCurrentItem(item)
            return
        }
        guard currentVersion != displayedFileVersion else { return }
        guard !hasUnsavedEdits else {
            errorMessage = "图片已在外部修改：\(item.url.lastPathComponent)"
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
            errorMessage = "图片已在外部修改且无法解码：\(item.url.lastPathComponent)"
        }
    }

    private func displayCurrentAndPreload(item: ImageItem, generation: UInt64) async {
        guard let loaded = try? await display(url: item.url, format: item.format),
              generation == displayRequestGeneration,
              navigationState?.currentItem?.url == item.url else {
            return
        }
        currentImage = loaded.image
        persistedCurrentImage = loaded.image
        displayedFileVersion = loaded.version
        updateMetadata(url: item.url, format: item.format, image: loaded.image)
        loadPhase = .full
        preloadNeighbors()
    }

    private func display(url: URL, format: SupportedImageFormat) async throws -> VersionedLoadedImage {
        try await loadImageAtURL(url, format)
    }

    private func removeExternallyUnavailableCurrentItem(_ item: ImageItem) {
        navigationState?.removeCurrent()
        displayedFileVersion = nil
        errorMessage = "文件已在外部移除：\(item.url.lastPathComponent)"

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
        let generation = beginDisplayRequest()
        loadPhase = .loading
        Task { await displayCurrentAndPreload(item: item, generation: generation) }
    }

    private func beginDisplayRequest() -> UInt64 {
        cancelActiveProgressiveLoad?()
        cancelActiveProgressiveLoad = nil
        displayRequestGeneration &+= 1
        return displayRequestGeneration
    }

    private func preloadNeighbors() {
        guard let state = navigationState, let current = state.currentItem else { return }
        let currentURL = current.url
        let currentIndex = state.items.firstIndex { $0.url == currentURL } ?? 0
        let neighbors: [ImageItem] = state.items.enumerated().compactMap { entry -> ImageItem? in
            let (index, item) = entry
            guard abs(index - currentIndex) <= 2,
                  Self.canPreloadInBackground(item.format) else {
                return nil
            }
            return item
        }

        guard !neighbors.isEmpty else { return }
        let decodeImageAtURL = self.decodeImageAtURL
        let currentFileVersionAtURL = self.currentFileVersionAtURL
        Task.detached { [cache] in
            for item in neighbors {
                guard let beforeVersion = currentFileVersionAtURL(item.url) else { continue }
                guard await cache.image(for: item.url, matching: beforeVersion) == nil else { continue }
                guard let decoded = try? decodeImageAtURL(item.url, item.format),
                      let afterVersion = currentFileVersionAtURL(item.url),
                      beforeVersion == afterVersion else { continue }
                await cache.insert(decoded, for: item.url, version: beforeVersion)
            }
        }
    }

    static func canPreloadInBackground(_ format: SupportedImageFormat) -> Bool {
        switch format {
        case .gif, .svg, .webp, .avif:
            return false
        case .jpeg, .png, .tiff, .bmp, .heic, .heif:
            return true
        }
    }

    private func updateDisplayTitle() {
        displayTitle = Self.displayTitle(filename: currentFilename, hasUnsavedEdits: hasUnsavedEdits)
    }

    static func displayTitle(filename: String, hasUnsavedEdits: Bool) -> String {
        hasUnsavedEdits ? "\(filename) - Edited" : filename
    }

    private func updateMetadata(url: URL, format: SupportedImageFormat, image: DecodedImage) {
        currentMetadata = metadataService.metadata(
            for: url,
            format: format,
            pixelWidth: image.cgImage.width,
            pixelHeight: image.cgImage.height
        )
    }

    private func restoredCurrentImage() throws -> DecodedImage {
        if let persistedCurrentImage {
            return persistedCurrentImage
        }

        guard let item = navigationState?.currentItem else {
            throw ImageDecodeError.cannotDecodeImage
        }

        return try decodeImageAtURL(item.url, item.format)
    }
}
