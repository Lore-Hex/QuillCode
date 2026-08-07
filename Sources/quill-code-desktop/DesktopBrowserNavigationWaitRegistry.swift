import Foundation

/// Owns the single in-flight visible-browser navigation for each tab.
///
/// WebKit can deliver an old navigation callback after a newer load has started. Correlating the
/// callback with the navigation object prevents that stale event from releasing the newer waiter.
/// Every exit path removes the continuation and cancels its timeout task before resuming it.
@MainActor
final class DesktopBrowserNavigationWaitRegistry {
    private struct Waiter {
        let requestID: UUID
        let continuation: CheckedContinuation<Void, any Error>
        let timeoutTask: Task<Void, Never>
        var navigationID: ObjectIdentifier?
    }

    private let timeoutNanoseconds: UInt64
    private var waitersByTabID: [UUID: Waiter] = [:]

    init(timeoutNanoseconds: UInt64) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    var activeCount: Int {
        waitersByTabID.count
    }

    func wait(for tabID: UUID, start: () -> AnyObject?) async throws {
        let requestID = UUID()

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                finish(
                    tabID: tabID,
                    error: DesktopBrowserSessionScriptError.navigationSuperseded
                )

                let timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: self?.timeoutNanoseconds ?? 0)
                    } catch {
                        return
                    }
                    self?.finish(tabID: tabID, requestID: requestID, error: nil)
                }
                waitersByTabID[tabID] = Waiter(
                    requestID: requestID,
                    continuation: continuation,
                    timeoutTask: timeoutTask,
                    navigationID: nil
                )

                let navigationID = start().map(ObjectIdentifier.init)
                guard var waiter = waitersByTabID[tabID], waiter.requestID == requestID else {
                    return
                }
                waiter.navigationID = navigationID
                waitersByTabID[tabID] = waiter
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(
                    tabID: tabID,
                    requestID: requestID,
                    error: CancellationError()
                )
            }
        }
    }

    /// Resolves only the waiter associated with `navigation`. A callback from an older WebKit load
    /// is ignored when a newer request owns the tab.
    @discardableResult
    func resolve(for tabID: UUID, navigation: AnyObject?, error: (any Error)?) -> Bool {
        guard let waiter = waitersByTabID[tabID] else { return false }
        if let expectedNavigationID = waiter.navigationID {
            guard let navigationID = navigation.map(ObjectIdentifier.init),
                  expectedNavigationID == navigationID
            else {
                return false
            }
        }
        return finish(tabID: tabID, requestID: waiter.requestID, error: error)
    }

    @discardableResult
    func finish(tabID: UUID, error: (any Error)?) -> Bool {
        guard let waiter = waitersByTabID[tabID] else { return false }
        return finish(tabID: tabID, requestID: waiter.requestID, error: error)
    }

    func finishAll(error: any Error) {
        for tabID in Array(waitersByTabID.keys) {
            finish(tabID: tabID, error: error)
        }
    }

    @discardableResult
    private func finish(tabID: UUID, requestID: UUID, error: (any Error)?) -> Bool {
        guard let waiter = waitersByTabID[tabID], waiter.requestID == requestID else {
            return false
        }

        waitersByTabID.removeValue(forKey: tabID)
        waiter.timeoutTask.cancel()
        if let error {
            waiter.continuation.resume(throwing: error)
        } else {
            waiter.continuation.resume()
        }
        return true
    }
}
