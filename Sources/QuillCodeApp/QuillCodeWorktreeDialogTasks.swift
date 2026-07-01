import Foundation

@MainActor
final class QuillCodeWorktreeDialogTasks {
    private enum Slot {
        case choiceLoad
        case prunePreview
    }

    private var runningTasks: [Slot: Task<Void, Never>] = [:]

    deinit {
        runningTasks.values.forEach { $0.cancel() }
    }

    func runChoiceLoad(_ operation: @escaping () async -> Void) {
        run(operation, in: .choiceLoad)
    }

    func runPrunePreview(_ operation: @escaping () async -> Void) {
        run(operation, in: .prunePreview)
    }

    func cancelPending() {
        runningTasks.values.forEach { $0.cancel() }
        runningTasks.removeAll()
    }

    func cancelChoiceLoad() {
        cancel(.choiceLoad)
    }

    func cancelPrunePreview() {
        cancel(.prunePreview)
    }

    private func run(_ operation: @escaping () async -> Void, in slot: Slot) {
        cancel(slot)
        runningTasks[slot] = Task { await operation() }
    }

    private func cancel(_ slot: Slot) {
        runningTasks.removeValue(forKey: slot)?.cancel()
    }
}
