import AppKit
import Foundation
import ImageViewCore

final class ThumbnailProvider {
    typealias Completion = @Sendable (Result<NSImage, Error>) -> Void
    typealias Loader = @Sendable (ImageItem, CGFloat, @escaping Completion) -> @Sendable () -> Void

    static let defaultMaxPixelSize: CGFloat = 320

    private let maxPixelSize: CGFloat
    private let loader: Loader

    init(
        maxPixelSize: CGFloat = ThumbnailProvider.defaultMaxPixelSize,
        loader: Loader? = nil
    ) {
        self.maxPixelSize = maxPixelSize
        self.loader = loader ?? Self.loadDefaultThumbnail
    }

    @discardableResult
    func loadThumbnail(for item: ImageItem, completion: @escaping Completion) -> ThumbnailRequest {
        let request = ThumbnailRequest()
        let cancelLoader = loader(item, maxPixelSize) { result in
            guard !request.isCancelled else {
                return
            }
            completion(result)
        }
        request.setCancelHandler(cancelLoader)
        return request
    }

    private static func loadDefaultThumbnail(
        item: ImageItem,
        maxPixelSize: CGFloat,
        completion: @escaping Completion
    ) -> @Sendable () -> Void {
        let workItem = DispatchWorkItem {
            do {
                let decoded = try ImageDecodeService().decode(
                    url: item.url,
                    format: item.format,
                    maxPixelSize: maxPixelSize
                )
                let image = NSImage(cgImage: decoded.cgImage, size: decoded.pixelSize)
                DispatchQueue.main.async {
                    completion(.success(image))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        DispatchQueue.global(qos: .utility).async(execute: workItem)

        let cancellation = WorkItemCancellation(workItem: workItem)
        return { cancellation.cancel() }
    }
}

final class ThumbnailRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    fileprivate func setCancelHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        let shouldCancelImmediately = cancelled
        if shouldCancelImmediately {
            lock.unlock()
            handler()
        } else {
            onCancel = handler
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
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

private final class WorkItemCancellation: @unchecked Sendable {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}
