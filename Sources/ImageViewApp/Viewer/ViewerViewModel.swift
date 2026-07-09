import AppKit
import Combine
import Foundation
import ImageViewCore

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published private(set) var navigationState: NavigationState?
    @Published private(set) var currentImage: DecodedImage?
    @Published private(set) var errorMessage: String?

    private let scanContainingDirectory: @Sendable (URL) async throws -> [ImageItem]
    private let decodeImageAtURL: @Sendable (URL, SupportedImageFormat) throws -> DecodedImage
    private let cache = ImageCache(costLimit: 512 * 1024 * 1024)
    private var openGeneration: UInt64 = 0

    init(
        scanContainingDirectory: @escaping @Sendable (URL) async throws -> [ImageItem] = {
            let scanner = DirectoryScanner()
            return try await scanner.scan(containing: $0)
        },
        decodeImageAtURL: @escaping @Sendable (URL, SupportedImageFormat) throws -> DecodedImage = {
            let decoder = ImageDecodeService()
            return try decoder.decode(url: $0, format: $1, maxPixelSize: nil)
        }
    ) {
        self.scanContainingDirectory = scanContainingDirectory
        self.decodeImageAtURL = decodeImageAtURL
    }

    func open(url: URL) async {
        openGeneration += 1
        let generation = openGeneration
        errorMessage = nil

        do {
            guard let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
                throw ImageDecodeError.cannotCreateSource
            }

            let fallbackItem = ImageItem(url: url, format: format)
            try await display(url: url, format: format)
            guard generation == openGeneration else { return }

            let items = try await scanContainingDirectory(url)
            guard generation == openGeneration else { return }

            let navigationItems = items.contains { $0.url.standardizedFileURL == url.standardizedFileURL } ? items : [fallbackItem]
            navigationState = NavigationState(items: navigationItems, currentURL: url)
            preloadNeighbors()
        } catch {
            guard generation == openGeneration else { return }
            navigationState = nil
            currentImage = nil
            errorMessage = "无法打开图片：\(url.lastPathComponent)"
        }
    }

    func showNext() {
        navigationState?.moveNext()
        Task { await displayCurrentAndPreload() }
    }

    func showPrevious() {
        navigationState?.movePrevious()
        Task { await displayCurrentAndPreload() }
    }

    private func displayCurrentAndPreload() async {
        guard let item = navigationState?.currentItem else { return }
        try? await display(url: item.url, format: item.format)
        preloadNeighbors()
    }

    private func display(url: URL, format: SupportedImageFormat) async throws {
        if let cached = await cache.image(for: url) {
            currentImage = cached
            return
        }

        let decoded = try decodeImageAtURL(url, format)
        await cache.insert(decoded, for: url, cost: decoded.cgImage.bytesPerRow * decoded.cgImage.height)
        currentImage = decoded
    }

    private func preloadNeighbors() {
        guard let state = navigationState, let current = state.currentItem else { return }
        let currentURL = current.url
        let currentIndex = state.items.firstIndex { $0.url == currentURL } ?? 0
        let neighbors = state.items.enumerated().compactMap { index, item in
            abs(index - currentIndex) <= 2 ? item : nil
        }

        let decodeImageAtURL = self.decodeImageAtURL
        Task.detached { [cache] in
            for item in neighbors {
                if await cache.image(for: item.url) == nil,
                   let decoded = try? decodeImageAtURL(item.url, item.format) {
                    await cache.insert(decoded, for: item.url, cost: decoded.cgImage.bytesPerRow * decoded.cgImage.height)
                }
            }
        }
    }
}
