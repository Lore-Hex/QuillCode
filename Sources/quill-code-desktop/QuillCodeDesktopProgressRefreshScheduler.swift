import Foundation

@MainActor
final class QuillCodeDesktopProgressRefreshScheduler {
    private let delayNanoseconds: UInt64
    private var pendingTask: Task<Void, Never>?

    /// Full workspace surfaces are intentionally published at most twice per second. A refresh
    /// rebuilds and lays out the transcript, so token-rate publication can outrun SwiftUI on a long
    /// response even when requests are technically coalesced.
    init(delayNanoseconds: UInt64 = 500_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func request(_ refresh: @escaping @MainActor () -> Void) {
        guard pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            pendingTask = nil
            refresh()
        }
    }

    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
