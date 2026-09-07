import AppKit
import ImageViewCore

/// Owns timing and a small look-ahead buffer; frame I/O never runs on the main actor.
@MainActor
final class AnimationPlayer {
    static let maximumBufferedFrameCount = 2
    static let maximumBufferedByteCost = 64 * 1024 * 1024
    private static let executor = ImageDecodeExecutor(maxConcurrentDecodeCount: 2)

    var onFrameChanged: (() -> Void)?
    private(set) var currentIndex = 0
    private(set) var currentFrame: AnimatedFrame?
    private var image: DecodedImage?
    private var frames: [Int: AnimatedFrame] = [:]
    private var failedIndices: Set<Int> = []
    private var timer: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var deadline: TimeInterval?
    private var waitingForNextFrame = false
    private(set) var isRunning = false
    var bufferedFrameCount: Int { frames.count }
    var bufferedByteCost: Int { frames.values.reduce(0) { $0 + Self.cost($1) } }

    deinit { timer?.cancel(); prefetchTask?.cancel() }

    func configure(_ image: DecodedImage?) {
        generation &+= 1
        timer?.cancel()
        timer = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        frames.removeAll()
        failedIndices.removeAll()
        currentIndex = 0
        currentFrame = nil
        deadline = nil
        waitingForNextFrame = false
        self.image = image
        isRunning = image?.isAnimated == true && frameCount > 1
        guard isRunning, let image else { return }
        if let first = image.animationFrames.first {
            currentFrame = first
            scheduleNextFrame()
        } else {
            refill()
        }
    }

    func advance() {
        guard isRunning, let image else { return }
        timer?.cancel()
        timer = nil
        let next = (currentIndex + 1) % frameCount
        if image.animationFrames.isEmpty {
            guard let frame = frames.removeValue(forKey: next) else {
                if failedIndices.contains(next) { isRunning = false; return }
                waitingForNextFrame = true
                refill()
                return
            }
            currentFrame = frame
        } else {
            currentFrame = image.animationFrames[next]
        }
        currentIndex = next
        waitingForNextFrame = false
        let wanted = Set(desiredIndices)
        frames = frames.filter { wanted.contains($0.key) }
        onFrameChanged?()
        scheduleNextFrame()
        refill()
    }

    private var frameCount: Int {
        guard let image else { return 0 }
        return image.animationFrames.isEmpty ? (image.animationFrameSource?.frameCount ?? 0) : image.animationFrames.count
    }

    private var desiredIndices: [Int] {
        guard frameCount > 0 else { return [] }
        if currentFrame == nil { return [0] }
        return (1...min(Self.maximumBufferedFrameCount, frameCount - 1)).map { (currentIndex + $0) % frameCount }
    }

    private func nextRequest() -> (AnimatedFrameSource, Int)? {
        guard isRunning, let source = image?.animationFrameSource,
              let index = desiredIndices.first(where: { frames[$0] == nil && !failedIndices.contains($0) }) else { return nil }
        let estimatedCost = currentFrame.map(Self.cost) ?? 0
        // Always allow one upcoming frame, including a frame larger than the budget.
        // Additional look-ahead is admitted only when it fits the byte budget.
        if !frames.isEmpty && estimatedCost > Self.maximumBufferedByteCost - bufferedByteCost { return nil }
        return (source, index)
    }

    private func refill() {
        guard prefetchTask == nil, nextRequest() != nil else { return }
        let generation = generation
        prefetchTask = Task { [weak self] in
            while !Task.isCancelled, let request = self?.nextRequest() {
                let frame: AnimatedFrame?
                do {
                    frame = try await Self.executor.execute { request.0.frame(at: request.1) }
                } catch { break }
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                if !self.accept(frame, at: request.1) { break }
            }
            if let self, self.generation == generation { self.prefetchTask = nil }
        }
    }

    private func accept(_ frame: AnimatedFrame?, at index: Int) -> Bool {
        guard let frame else {
            failedIndices.insert(index)
            if currentFrame == nil || (waitingForNextFrame && index == (currentIndex + 1) % frameCount) { isRunning = false }
            return true
        }
        if currentFrame == nil && index == 0 {
            currentFrame = frame
            onFrameChanged?()
            scheduleNextFrame()
        } else if frames.isEmpty || Self.cost(frame) <= Self.maximumBufferedByteCost - bufferedByteCost {
            frames[index] = frame
            if waitingForNextFrame && index == (currentIndex + 1) % frameCount { advance() }
        } else {
            return false
        }
        return true
    }

    static func nextDeadline(previous: TimeInterval?, duration: TimeInterval, now: TimeInterval) -> TimeInterval {
        max((previous ?? now) + max(0.01, duration), now)
    }

    private func scheduleNextFrame() {
        guard isRunning, let currentFrame else { return }
        let now = ProcessInfo.processInfo.systemUptime
        deadline = Self.nextDeadline(previous: deadline, duration: currentFrame.duration, now: now)
        let delay = max(0.001, (deadline ?? now) - now)
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private static func cost(_ frame: AnimatedFrame) -> Int {
        let (cost, overflow) = frame.cgImage.bytesPerRow.multipliedReportingOverflow(by: frame.cgImage.height)
        return overflow ? Int.max : cost
    }
}
