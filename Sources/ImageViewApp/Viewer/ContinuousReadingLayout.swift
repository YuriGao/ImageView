import AppKit
import ImageViewCore

/// Geometry survives bitmap eviction and is rebuilt only for size/order changes.
struct ContinuousReadingLayout {
    private var ids: [ImageItem.ID] = []
    private var indexByID: [ImageItem.ID: Int] = [:]
    private var aspectRatios: [ImageItem.ID: CGFloat] = [:]
    private var frames: [CGRect] = []
    private var cachedWidth: CGFloat?
    private var isDirty = true
    private(set) var buildCount = 0

    mutating func update(_ pages: [ContinuousReadingPage]) {
        let newIDs = pages.map { $0.item.id }
        if ids != newIDs {
            ids = newIDs
            indexByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            aspectRatios = aspectRatios.filter { indexByID[$0.key] != nil }
            isDirty = true
        }
        for page in pages {
            guard let image = page.image, image.cgImage.width > 0 else { continue }
            let ratio = CGFloat(image.cgImage.height) / CGFloat(image.cgImage.width)
            if aspectRatios[page.item.id] != ratio {
                aspectRatios[page.item.id] = ratio
                isDirty = true
            }
        }
    }

    mutating func prepare(width: CGFloat) {
        guard isDirty || cachedWidth != width else { return }
        cachedWidth = width
        isDirty = false
        buildCount += 1
        let contentWidth = max(width - 32, 1)
        var y: CGFloat = 16
        frames = ids.map { id in
            let height = aspectRatios[id].map { contentWidth * $0 } ?? min(contentWidth * 0.75, 420)
            let frame = CGRect(x: 16, y: y, width: contentWidth, height: max(height, 1))
            y = frame.maxY + 18
            return frame
        }
    }

    var requiredHeight: CGFloat { frames.last?.maxY ?? 0 }
    func frame(at index: Int) -> CGRect { frames[index] }
    func frame(for id: ImageItem.ID) -> CGRect? { indexByID[id].map { frames[$0] } }

    func nearestItemID(to y: CGFloat) -> ImageItem.ID? {
        guard !frames.isEmpty else { return nil }
        let next = lowerBound { $0.midY >= y }
        if next == 0 { return ids[0] }
        if next == frames.count { return ids[next - 1] }
        return abs(frames[next - 1].midY - y) <= abs(frames[next].midY - y) ? ids[next - 1] : ids[next]
    }

    func index(at point: CGPoint) -> Int? {
        let index = lowerBound { $0.maxY >= point.y }
        return index < frames.count && frames[index].contains(point) ? index : nil
    }

    func visibleRange(in rect: CGRect) -> Range<Int> {
        let first = lowerBound { $0.maxY >= rect.minY }
        let end = lowerBound { $0.minY > rect.maxY }
        return first..<max(first, end)
    }

    private func lowerBound(_ predicate: (CGRect) -> Bool) -> Int {
        var low = 0
        var high = frames.count
        while low < high {
            let middle = low + (high - low) / 2
            if predicate(frames[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
