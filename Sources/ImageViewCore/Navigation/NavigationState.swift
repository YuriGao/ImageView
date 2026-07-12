import Foundation

public struct NavigationState: Equatable, Sendable {
    public private(set) var items: [ImageItem]
    public private(set) var currentIndex: Int?

    public init(items: [ImageItem], currentURL: URL) {
        self.items = items.sorted { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }
        self.currentIndex = self.items.firstIndex { $0.url == currentURL } ?? self.items.firstIndex { $0.url.standardizedFileURL == currentURL.standardizedFileURL }
    }

    public var currentItem: ImageItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public mutating func movePrevious() {
        guard let currentIndex, currentIndex > 0 else { return }
        self.currentIndex = currentIndex - 1
    }

    public mutating func moveNext() {
        guard let currentIndex, currentIndex < items.count - 1 else { return }
        self.currentIndex = currentIndex + 1
    }

    public mutating func removeCurrent() {
        guard let currentIndex, items.indices.contains(currentIndex) else { return }
        items.remove(at: currentIndex)
        if items.isEmpty {
            self.currentIndex = nil
        } else {
            self.currentIndex = min(currentIndex, items.count - 1)
        }
    }

    public mutating func replaceCurrentURL(_ newURL: URL, format: SupportedImageFormat) {
        guard let currentIndex, items.indices.contains(currentIndex) else { return }
        items[currentIndex] = ImageItem(url: newURL, format: format)
        items.sort { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }
        self.currentIndex = items.firstIndex { $0.url == newURL } ?? items.firstIndex { $0.url.standardizedFileURL == newURL.standardizedFileURL }
    }

    public mutating func applyURLMigrations(_ migrations: [URL: URL]) {
        guard !migrations.isEmpty else { return }
        let currentURL = currentItem?.url.standardizedFileURL
        let migratedCurrentURL = currentURL.flatMap { migrations[$0] }?.standardizedFileURL ?? currentURL
        items = items.map { item in
            let standardizedURL = item.url.standardizedFileURL
            guard let destination = migrations[standardizedURL] else { return item }
            return ImageItem(
                url: destination,
                format: SupportedImageFormat(fileExtension: destination.pathExtension) ?? item.format
            )
        }
        items.sort { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }
        currentIndex = migratedCurrentURL.flatMap { migratedCurrentURL in
            items.firstIndex { $0.url.standardizedFileURL == migratedCurrentURL }
        }
    }

    public mutating func removeItems(withURLs removedURLs: Set<URL>) {
        guard !removedURLs.isEmpty else { return }
        let previousCurrentURL = currentItem?.url.standardizedFileURL
        let previousCurrentIndex = currentIndex
        items.removeAll { removedURLs.contains($0.url.standardizedFileURL) }
        if let previousCurrentURL,
           let retainedIndex = items.firstIndex(where: { $0.url.standardizedFileURL == previousCurrentURL }) {
            currentIndex = retainedIndex
        } else if let previousCurrentIndex, !items.isEmpty {
            currentIndex = min(previousCurrentIndex, items.count - 1)
        } else {
            currentIndex = nil
        }
    }
}
