import Foundation

public final class ImageDecodeExecutor: @unchecked Sendable {
    public static let maximumConcurrentDecodeCount = 2
    public static let shared = ImageDecodeExecutor(maxConcurrentDecodeCount: maximumConcurrentDecodeCount)

    private let queue: OperationQueue
    var operationCount: Int { queue.operationCount }

    public init(maxConcurrentDecodeCount: Int) {
        queue = OperationQueue()
        queue.name = "ImageView.full-image-decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentDecodeCount)
    }

    public func decode(
        priority: ImageDecodePriority = ImageDecodePriority(),
        _ operation: @escaping @Sendable () throws -> DecodedImage
    ) async throws -> DecodedImage {
        try await execute(priority: priority, operation)
    }

    public func execute<Value: Sendable>(
        priority: ImageDecodePriority = ImageDecodePriority(),
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let request = DecodeExecutionRequest<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard request.install(continuation: continuation) else { return }
                let work = BlockOperation()
                work.addExecutionBlock {
                    request.execute(operation)
                }
                request.install(operation: work)
                priority.register(work)
                queue.addOperation(work)
            }
        } onCancel: {
            request.cancel()
        }
    }
}

private final class DecodeExecutionRequest<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var operation: Operation?
    private var completed = false

    func install(continuation: CheckedContinuation<Value, Error>) -> Bool {
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

    func execute(_ body: @escaping @Sendable () throws -> Value) {
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

    private func finish(_ result: Result<Value, Error>) {
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

/// A visible consumer can promote a queued prefetch without starting another decode.
public final class ImageDecodePriority: @unchecked Sendable {
    private let lock = NSLock()
    private var interactive: Bool
    private weak var operation: Operation?

    public init(interactive: Bool = true) { self.interactive = interactive }

    public func promote() {
        lock.withLock {
            interactive = true
            operation?.queuePriority = .veryHigh
        }
    }

    fileprivate func register(_ operation: Operation) {
        lock.withLock {
            self.operation = operation
            operation.queuePriority = interactive ? .veryHigh : .low
        }
    }
}
