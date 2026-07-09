import Foundation

public actor ImageCache {
    private struct Entry {
        let image: DecodedImage
        let cost: Int
        var lastAccess: UInt64
    }

    private var entries: [URL: Entry] = [:]
    private var totalCost: Int = 0
    private var tick: UInt64 = 0
    private let costLimit: Int

    public init(costLimit: Int) {
        self.costLimit = max(1, costLimit)
    }

    public func image(for url: URL) -> DecodedImage? {
        guard var entry = entries[url] else {
            return nil
        }

        tick += 1
        entry.lastAccess = tick
        entries[url] = entry
        return entry.image
    }

    public func insert(_ image: DecodedImage, for url: URL, cost: Int) {
        let normalizedCost = max(1, cost)

        if let existing = entries[url] {
            totalCost -= existing.cost
        }

        tick += 1
        entries[url] = Entry(image: image, cost: normalizedCost, lastAccess: tick)
        totalCost += normalizedCost
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while totalCost > costLimit,
              let victim = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            entries.removeValue(forKey: victim.key)
            totalCost -= victim.value.cost
        }
    }
}
