import Foundation

/// Coalesces high-frequency model progress into a responsive, bounded presentation cadence.
/// Authoritative workspace state is updated before this scheduler is called; only the expensive
/// `WorkspaceSurface` projection is delayed.
@MainActor
final class QuillCodeDesktopProgressRefreshScheduler {
    static let defaultDelayNanoseconds: UInt64 = 50_000_000

    private let delayNanoseconds: UInt64
    private var pendingAction: (() -> Void)?
    private var pendingTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(delayNanoseconds: UInt64 = defaultDelayNanoseconds) {
        self.delayNanoseconds = delayNanoseconds
    }

    deinit {
        pendingTask?.cancel()
    }

    var hasPendingRefresh: Bool {
        pendingTask != nil
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        pendingAction = action
        guard pendingTask == nil else { return }

        generation &+= 1
        let scheduledGeneration = generation
        let delayNanoseconds = delayNanoseconds
        pendingTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                self?.clearIfCurrent(scheduledGeneration)
                return
            }
            self?.runIfCurrent(scheduledGeneration)
        }
    }

    /// Publishes terminal or user-driven state now and invalidates any delayed projection.
    func flush(_ action: @MainActor () -> Void) {
        cancel()
        action()
    }

    func cancel() {
        generation &+= 1
        pendingAction = nil
        pendingTask?.cancel()
        pendingTask = nil
    }

    private func runIfCurrent(_ scheduledGeneration: UInt64) {
        guard generation == scheduledGeneration else { return }
        let action = pendingAction
        pendingAction = nil
        pendingTask = nil
        action?()
    }

    private func clearIfCurrent(_ scheduledGeneration: UInt64) {
        guard generation == scheduledGeneration else { return }
        pendingAction = nil
        pendingTask = nil
    }
}
