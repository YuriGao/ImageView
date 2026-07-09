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
    private let loadImageAtURL: @Sendable (URL, SupportedImageFormat) async throws -> DecodedImage
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
        },
        loadImageAtURL: (@Sendable (URL, SupportedImageFormat) async throws -> DecodedImage)? = nil
    ) {
        self.scanContainingDirectory = scanContainingDirectory
        self.decodeImageAtURL = decodeImageAtURL
        if let loadImageAtURL {
            self.loadImageAtURL = loadImageAtURL
        } else {
            let cache = self.cache
            self.loadImageAtURL = { url, format in
                if let cached = await cache.image(for: url) {
                    return cached
                }

                let decoded = try decodeImageAtURL(url, format)
                await cache.insert(decoded, for: url, cost: decoded.cgImage.bytesPerRow * decoded.cgImage.height)
                return decoded
            }
        }
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
            let image = try await display(url: url, format: format)
            guard generation == openGeneration else { return }
            currentImage = image
            navigationState = NavigationState(items: [fallbackItem], currentURL: url)

            do {
                let items = try await scanContainingDirectory(url)
                guard generation == openGeneration else { return }

                if items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                    navigationState = NavigationState(items: items, currentURL: url)
                }
            } catch {
                guard generation == openGeneration else { return }
            }

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
        guard let image = try? await display(url: item.url, format: item.format),
              navigationState?.currentItem?.url == item.url else {
            return
        }
        currentImage = image
        preloadNeighbors()
    }

    private func display(url: URL, format: SupportedImageFormat) async throws -> DecodedImage {
        try await loadImageAtURL(url, format)
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
