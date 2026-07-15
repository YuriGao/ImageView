import Foundation

public final class ImageDecodeExecutor: @unchecked Sendable {
    public static let maximumConcurrentDecodeCount = 2
    public static let shared = ImageDecodeExecutor(maxConcurrentDecodeCount: maximumConcurrentDecodeCount)

    private let queue: OperationQueue

    public init(maxConcurrentDecodeCount: Int) {
        queue = OperationQueue()
        queue.name = "ImageView.full-image-decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentDecodeCount)
    }

    public func decode(
        _ operation: @escaping @Sendable () throws -> DecodedImage
    ) async throws -> DecodedImage {
        let request = DecodeExecutionRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard request.install(continuation: continuation) else { return }
                let work = BlockOperation()
                work.addExecutionBlock {
                    request.execute(operation)
                }
                request.install(operation: work)
                queue.addOperation(work)
            }
        } onCancel: {
            request.cancel()
        }
    }
}

private final class DecodeExecutionRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DecodedImage, Error>?
    private var operation: Operation?
    private var completed = false

    func install(continuation: CheckedContinuation<DecodedImage, Error>) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func install(operation: Operation) {
        lock.lock()
        if completed {
            lock.unlock()
            operation.cancel()
            return
        }
        self.operation = operation
        lock.unlock()
    }

    func execute(_ body: @escaping @Sendable () throws -> DecodedImage) {
        lock.lock()
        let shouldRun = !completed
        lock.unlock()
        guard shouldRun else { return }

        do {
            finish(.success(try body()))
        } catch {
            finish(.failure(error))
        }
    }

    func cancel() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        let operation = self.operation
        self.operation = nil
        lock.unlock()

        operation?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<DecodedImage, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        operation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
