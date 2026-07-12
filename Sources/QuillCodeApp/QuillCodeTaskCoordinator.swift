import Foundation

@MainActor
public final class QuillCodeTaskCoordinator<Slot: Hashable & Sendable> {
    private struct RunningTask: Sendable {
        var id: UUID
        var task: Task<Void, Never>
    }

    private var tasks: [Slot: RunningTask] = [:]

    public init() {}

    deinit {
        tasks.values.forEach { $0.task.cancel() }
    }

    public func isRunning(_ slot: Slot) -> Bool {
        tasks[slot] != nil
    }

    public var runningSlots: Set<Slot> {
        Set(tasks.keys)
    }

    @discardableResult
    public func startIfIdle(
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

    public func replace(
        _ slot: Slot,
        operation: @escaping @MainActor () async -> Void,
        onFinish: @escaping @MainActor () -> Void = {}
    ) {
        cancel(slot)
        start(slot, operation: operation, onFinish: onFinish)
    }

    public func cancel(_ slot: Slot) {
        tasks.removeValue(forKey: slot)?.task.cancel()
    }

    public func cancel(_ slots: [Slot]) {
        slots.forEach(cancel)
    }

    public func cancelAll() {
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
                guard self?.finish(slot, id: id) == true else { return }
                onFinish()
            }
        )
    }

    private func finish(_ slot: Slot, id: UUID) -> Bool {
        guard tasks[slot]?.id == id else {
            return false
        }
        tasks.removeValue(forKey: slot)
        return true
    }
}
