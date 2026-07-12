import Foundation
import QuillCodeApp

@MainActor
final class QuillCodeDesktopTaskCoordinator {
    enum Slot: Hashable, Sendable {
        case send(UUID?)
        case terminal
        case browserPreview
        case automationTicker
        case modelCatalogRefresh
        case modelCatalogRefreshTicker
    }

    private let coordinator = QuillCodeTaskCoordinator<Slot>()

    func isRunning(_ slot: Slot) -> Bool {
        coordinator.isRunning(slot)
    }

    func isSendRunning(threadID: UUID?) -> Bool {
        coordinator.isRunning(.send(threadID))
    }

    var runningSendThreadIDs: Set<UUID> {
        Set(runningSendSlots.compactMap { slot in
            guard case .send(let threadID) = slot else { return nil }
            return threadID
        })
    }

    @discardableResult
    func startIfIdle(
        _ slot: Slot,
        operation: @escaping @MainActor () async -> Void,
        onFinish: @escaping @MainActor () -> Void = {}
    ) -> Bool {
        coordinator.startIfIdle(slot, operation: operation, onFinish: onFinish)
    }

    func replace(
        _ slot: Slot,
        operation: @escaping @MainActor () async -> Void,
        onFinish: @escaping @MainActor () -> Void = {}
    ) {
        coordinator.replace(slot, operation: operation, onFinish: onFinish)
    }

    func cancel(_ slot: Slot) {
        coordinator.cancel(slot)
    }

    func cancel(_ slots: [Slot]) {
        coordinator.cancel(slots)
    }

    func cancelAll() {
        coordinator.cancelAll()
    }

    func cancelAllSends() {
        coordinator.cancel(Array(runningSendSlots))
    }

    private var runningSendSlots: Set<Slot> {
        coordinator.runningSlots.filter { slot in
            if case .send = slot { return true }
            return false
        }
    }
}
