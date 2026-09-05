import Foundation

@MainActor
final class OverlayAutoHideScheduler {
    private var task: Task<Void, Never>?
    private(set) var generation: UInt64 = 0

    deinit { task?.cancel() }

    func cancel() {
        task?.cancel()
        task = nil
        generation &+= 1
    }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        let generation = generation
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard self?.generation == generation, !Task.isCancelled else { return }
            action()
        }
    }
}
