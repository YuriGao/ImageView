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
    private struct Request {
        let id: UUID
        let task: Task<Void, Never>
        let priority: ImageDecodePriority
        var waiters: [UUID: CheckedContinuation<DecodedImage, Error>]
    }
    private var inFlight: [RequestKey: Request] = [:]
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
        try await loadImage(for: url, matching: version, priority: Task.currentPriority) { _ in
            try await loader()
        }
    }

    public func loadImage(
        for url: URL,
        matching version: CurrentFileVersion,
        priority: TaskPriority,
        loader: @escaping @Sendable (ImageDecodePriority) async throws -> DecodedImage
    ) async throws -> DecodedImage {
        try Task.checkCancellation()
        if let cached = image(for: url, matching: version) { return cached }
        let key = RequestKey(url: url.standardizedFileURL, version: version)
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if var request = inFlight[key] {
                    if priority >= .medium { request.priority.promote() }
                    request.waiters[waiterID] = continuation
                    inFlight[key] = request
                    return
                }
                let requestID = UUID()
                let decodePriority = ImageDecodePriority(interactive: priority >= .medium)
                let task = Task(priority: priority) {
                    let result: Result<DecodedImage, Error>
                    do {
                        try Task.checkCancellation()
                        let decoded = try await loader(decodePriority)
                        try Task.checkCancellation()
                        result = .success(decoded)
                    } catch { result = .failure(error) }
                    self.complete(key, requestID: requestID, result: result)
                }
                inFlight[key] = Request(id: requestID, task: task, priority: decodePriority, waiters: [waiterID: continuation])
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, for: key) }
        }
    }

    private func cancelWaiter(_ waiterID: UUID, for key: RequestKey) {
        guard var request = inFlight[key], let waiter = request.waiters.removeValue(forKey: waiterID) else { return }
        if request.waiters.isEmpty {
            inFlight.removeValue(forKey: key)
            request.task.cancel()
        } else {
            inFlight[key] = request
        }
        waiter.resume(throwing: CancellationError())
    }

    private func complete(_ key: RequestKey, requestID: UUID, result: Result<DecodedImage, Error>) {
        // Invalidated work may finish after a replacement request for the same key.
        guard let request = inFlight[key], request.id == requestID else { return }
        inFlight.removeValue(forKey: key)
        if case .success(let decoded) = result { insert(decoded, for: key.url, version: key.version) }
        for waiter in request.waiters.values { waiter.resume(with: result) }
    }

    public func removeImage(for url: URL) {
        let standardizedURL = url.standardizedFileURL
        if let entry = entries.removeValue(forKey: standardizedURL) {
            totalCost -= entry.cost
        }
        for key in inFlight.keys.filter({ $0.url == standardizedURL }) {
            guard let request = inFlight.removeValue(forKey: key) else { continue }
            request.task.cancel()
            for waiter in request.waiters.values { waiter.resume(throwing: CancellationError()) }
        }
    }

    public func currentCost() -> Int {
        totalCost
    }

    func consumerCount(for url: URL) -> Int {
        inFlight.filter { $0.key.url == url.standardizedFileURL }.values.reduce(0) { $0 + $1.waiters.count }
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
