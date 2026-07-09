import Foundation

public struct NavigationState: Equatable {
    var items: [ImageItem]
    var currentIndex: Int?

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
}
