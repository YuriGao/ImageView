import Foundation

public actor ImageCache {
    public static let defaultFullImageCostLimit = 512 * 1024 * 1024
    public static let defaultThumbnailCostLimit = 128 * 1024 * 1024
    public static let shared = ImageCache(costLimit: defaultFullImageCostLimit)

    private struct RequestKey: Hashable {
        let url: URL
        let version: CurrentFileVersion
    }

    private struct Entry {
        let image: DecodedImage
        let version: CurrentFileVersion
        let cost: Int
        var lastAccess: UInt64
    }

    private var entries: [URL: Entry] = [:]
    private var totalCost: Int = 0
    private var tick: UInt64 = 0
    private var inFlight: [RequestKey: Task<DecodedImage, Error>] = [:]
    private let costLimit: Int

    public init(costLimit: Int = ImageCache.defaultFullImageCostLimit) {
        self.costLimit = max(1, costLimit)
    }

    public func image(for url: URL, matching version: CurrentFileVersion) -> DecodedImage? {
        let key = url.standardizedFileURL
        guard var entry = entries[key] else {
            return nil
        }
        guard entry.version == version else {
            entries.removeValue(forKey: key)
            totalCost -= entry.cost
            return nil
        }

        tick += 1
        entry.lastAccess = tick
        entries[key] = entry
        return entry.image
    }

    public func insert(_ image: DecodedImage, for url: URL, version: CurrentFileVersion) {
        let normalizedCost = max(1, image.decodedByteCost)
        let key = url.standardizedFileURL

        if let existing = entries[key] {
            totalCost -= existing.cost
        }

        tick += 1
        entries[key] = Entry(image: image, version: version, cost: normalizedCost, lastAccess: tick)
        totalCost = DecodedImage.saturatedSum(totalCost, normalizedCost)
        evictIfNeeded()
    }

    public func loadImage(
        for url: URL,
        matching version: CurrentFileVersion,
        loader: @escaping @Sendable () async throws -> DecodedImage
    ) async throws -> DecodedImage {
        if let cached = image(for: url, matching: version) {
            return cached
        }

        let key = RequestKey(url: url.standardizedFileURL, version: version)
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task<DecodedImage, Error> {
            try await loader()
        }
        inFlight[key] = task

        do {
            let decoded = try await task.value
            inFlight.removeValue(forKey: key)
            insert(decoded, for: url, version: version)
            return decoded
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }

    public func removeImage(for url: URL) {
        let standardizedURL = url.standardizedFileURL
        if let entry = entries.removeValue(forKey: standardizedURL) {
            totalCost -= entry.cost
        }
        let matchingKeys = inFlight.keys.filter { $0.url == standardizedURL }
        for key in matchingKeys {
            inFlight.removeValue(forKey: key)?.cancel()
        }
    }

    public func currentCost() -> Int {
        totalCost
    }

    public func inFlightRequestCount() -> Int {
        inFlight.count
    }

    private func evictIfNeeded() {
        while totalCost > costLimit,
              let victim = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            entries.removeValue(forKey: victim.key)
            totalCost -= victim.value.cost
        }
    }
}
