import AppKit
import Combine
import Foundation
import ImageViewCore

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published private(set) var navigationState: NavigationState?
    @Published private(set) var currentImage: DecodedImage?
    @Published private(set) var errorMessage: String?

    private let scanner = DirectoryScanner()
    private let decoder = ImageDecodeService()
    private let cache = ImageCache(costLimit: 512 * 1024 * 1024)

    func open(url: URL) async {
        errorMessage = nil
        do {
            let format = SupportedImageFormat(fileExtension: url.pathExtension)
            let fallbackItems = format.map { [ImageItem(url: url, format: $0)] } ?? []
            navigationState = NavigationState(items: fallbackItems, currentURL: url)
            try await display(url: url)

            let items = try await scanner.scan(containing: url)
            navigationState = NavigationState(items: items, currentURL: url)
            preloadNeighbors()
        } catch {
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
        guard let url = navigationState?.currentItem?.url else { return }
        try? await display(url: url)
        preloadNeighbors()
    }

    private func display(url: URL) async throws {
        if let cached = await cache.image(for: url) {
            currentImage = cached
            return
        }

        let format = navigationState?.currentItem?.format ?? SupportedImageFormat(fileExtension: url.pathExtension) ?? .png
        let decoded = try decoder.decode(url: url, format: format, maxPixelSize: nil)
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

        Task.detached { [decoder, cache] in
            for item in neighbors {
                if await cache.image(for: item.url) == nil,
                   let decoded = try? decoder.decode(url: item.url, format: item.format, maxPixelSize: nil) {
                    await cache.insert(decoded, for: item.url, cost: decoded.cgImage.bytesPerRow * decoded.cgImage.height)
                }
            }
        }
    }
}
