import Foundation

@MainActor
final class QuillCodeDesktopTaskCoordinator {
    enum Slot: Hashable {
        case send
        case terminal
        case browserPreview
        case automationTicker
    }

    private struct RunningTask {
        var id: UUID
        var task: Task<Void, Never>
    }

    private var tasks: [Slot: RunningTask] = [:]

    deinit {
        tasks.values.forEach { $0.task.cancel() }
    }

    func isRunning(_ slot: Slot) -> Bool {
        tasks[slot] != nil
    }

    @discardableResult
    func startIfIdle(
        _ slot: Slot,
        operation: @escaping @MainActor () async -> Void,
        onFinish: @escaping @MainActor () -> Void = {}
    ) -> Bool {
        guard tasks[slot] == nil else {
            return false
        }
        start(slot, operation: operation, onFinish: onFinish)
        return true
    }

    func replace(
        _ slot: Slot,
        operation: @escaping @MainActor () async -> Void,
        onFinish: @escaping @MainActor () -> Void = {}
    ) {
        cancel(slot)
        start(slot, operation: operation, onFinish: onFinish)
    }

    func cancel(_ slot: Slot) {
        tasks.removeValue(forKey: slot)?.task.cancel()
    }

    func cancel(_ slots: [Slot]) {
        slots.forEach(cancel)
    }

    func cancelAll() {
        let runningTasks = tasks.values.map(\.task)
        tasks.removeAll()
        runningTasks.forEach { $0.cancel() }
    }

    private func start(
        _ slot: Slot,
        operation: @escaping @MainActor () async -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) {
        let id = UUID()
        tasks[slot] = RunningTask(
            id: id,
            task: Task { @MainActor [weak self] in
                await operation()
                self?.finish(slot, id: id)
                onFinish()
            }
        )
    }

    private func finish(_ slot: Slot, id: UUID) {
        guard tasks[slot]?.id == id else {
            return
        }
        tasks.removeValue(forKey: slot)
    }
}
