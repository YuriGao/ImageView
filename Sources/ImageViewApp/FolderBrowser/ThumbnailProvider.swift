import AppKit
import Foundation
import ImageViewCore

final class ThumbnailProvider {
    typealias Completion = @Sendable (Result<NSImage, Error>) -> Void
    typealias Loader = @Sendable (ImageItem, CGFloat, @escaping Completion) -> @Sendable () -> Void
    typealias Decoder = @Sendable (ImageItem, CGFloat) throws -> DecodedImage

    static let defaultMaxPixelSize: CGFloat = 320
    static let maximumConcurrentDecodeCount = 4

    private static let cache = ThumbnailCacheStorage()
    private static let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ImageView.thumbnail-decode"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = maximumConcurrentDecodeCount
        return queue
    }()

    private let maxPixelSize: CGFloat
    private let loader: Loader

    init(
        maxPixelSize: CGFloat = ThumbnailProvider.defaultMaxPixelSize,
        loader: Loader? = nil,
        currentFileVersionAtURL: @escaping @Sendable (URL) -> CurrentFileVersion? = CurrentFileVersion.read(at:),
        decoder: Decoder? = nil
    ) {
        self.maxPixelSize = maxPixelSize
        let resolvedDecoder = decoder ?? { item, maxPixelSize in
            try ImageDecodeService().decode(
                url: item.url,
                format: item.format,
                maxPixelSize: maxPixelSize
            )
        }
        self.loader = loader ?? { item, maxPixelSize, completion in
            Self.loadDefaultThumbnail(
                item: item,
                maxPixelSize: maxPixelSize,
                currentFileVersionAtURL: currentFileVersionAtURL,
                decoder: resolvedDecoder,
                completion: completion
            )
        }
    }

    @discardableResult
    func loadThumbnail(for item: ImageItem, completion: @escaping Completion) -> ThumbnailRequest {
        let request = ThumbnailRequest()
        let cancelLoader = loader(item, maxPixelSize) { result in
            guard request.completeIfActive() else { return }
            completion(result)
        }
        request.setCancelHandler(cancelLoader)
        return request
    }

    private static func loadDefaultThumbnail(
        item: ImageItem,
        maxPixelSize: CGFloat,
        currentFileVersionAtURL: @escaping @Sendable (URL) -> CurrentFileVersion?,
        decoder: @escaping Decoder,
        completion: @escaping Completion
    ) -> @Sendable () -> Void {
        let version = currentFileVersionAtURL(item.url)
        let key = ThumbnailCacheKey(url: item.url, version: version, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) {
            DispatchQueue.main.async {
                completion(.success(cached))
            }
            return {}
        }

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard operation?.isCancelled == false else { return }
            do {
                let decoded = try decoder(item, maxPixelSize)
                guard operation?.isCancelled == false else { return }
                guard currentFileVersionAtURL(item.url) == version else {
                    DispatchQueue.main.async { [weak operation] in
                        guard operation?.isCancelled == false else { return }
                        completion(.failure(ImageDecodeError.cannotDecodeImage))
                    }
                    return
                }
                let image = NSImage(cgImage: decoded.cgImage, size: decoded.pixelSize)
                cache.setObject(image, forKey: key, cost: decoded.decodedByteCost)
                DispatchQueue.main.async { [weak operation] in
                    guard operation?.isCancelled == false else { return }
                    completion(.success(image))
                }
            } catch {
                DispatchQueue.main.async { [weak operation] in
                    guard operation?.isCancelled == false else { return }
                    completion(.failure(error))
                }
            }
        }
        decodeQueue.addOperation(operation)

        let cancellation = OperationCancellation(operation: operation)
        return { cancellation.cancel() }
    }

    static func removeAllCachedThumbnailsForTesting() {
        cache.removeAllObjects()
    }
}

private final class ThumbnailCacheStorage: @unchecked Sendable {
    private let cache = NSCache<ThumbnailCacheKey, NSImage>()

    init() {
        cache.totalCostLimit = ImageCache.defaultThumbnailCostLimit
    }

    func object(forKey key: ThumbnailCacheKey) -> NSImage? {
        cache.object(forKey: key)
    }

    func setObject(_ image: NSImage, forKey key: ThumbnailCacheKey, cost: Int) {
        cache.setObject(image, forKey: key, cost: cost)
    }

    func removeAllObjects() {
        cache.removeAllObjects()
    }
}

private final class ThumbnailCacheKey: NSObject, @unchecked Sendable {
    private let url: URL
    private let version: CurrentFileVersion?
    private let maxPixelSize: Int

    init(url: URL, version: CurrentFileVersion?, maxPixelSize: CGFloat) {
        self.url = url.standardizedFileURL
        self.version = version
        self.maxPixelSize = Int(maxPixelSize.rounded(.up))
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(url)
        hasher.combine(version)
        hasher.combine(maxPixelSize)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ThumbnailCacheKey else { return false }
        return url == other.url && version == other.version && maxPixelSize == other.maxPixelSize
    }
}

final class ThumbnailRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?
    private var cancelled = false
    private var finished = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    fileprivate func setCancelHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        let shouldCancelImmediately = cancelled
        if finished {
            lock.unlock()
        } else if shouldCancelImmediately {
            lock.unlock()
            handler()
        } else {
            onCancel = handler
            lock.unlock()
        }
    }

    fileprivate func completeIfActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, !finished else { return false }
        finished = true
        onCancel = nil
        return true
    }

    func cancel() {
        lock.lock()
        guard !cancelled, !finished else {
            lock.unlock()
            return
        }

        cancelled = true
        let handler = onCancel
        onCancel = nil
        lock.unlock()
        handler?()
    }
}

private final class OperationCancellation: @unchecked Sendable {
    private let operation: Operation

    init(operation: Operation) {
        self.operation = operation
    }

    func cancel() {
        operation.cancel()
    }
}
