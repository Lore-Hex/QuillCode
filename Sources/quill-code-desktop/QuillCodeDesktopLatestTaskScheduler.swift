import Foundation

/// Runs at most one asynchronous operation per key while retaining only the newest pending request.
///
/// UI events can arrive faster than an expensive projection finishes. Starting one task per event
/// wastes work and lets stale results publish after newer state. This scheduler bounds each key to
/// one active operation plus one latest-wins pending request and suppresses an active result when a
/// newer request arrived while it was running.
@MainActor
final class QuillCodeDesktopLatestTaskScheduler<Key: Hashable & Sendable, Input, Output> {
    typealias Operation = @MainActor (Input) async throws -> Output
    typealias Delivery = @MainActor (Input, Output) -> Void

    private struct PendingWork {
        var input: Input
    }

    private struct Worker {
        var id: UUID
        var task: Task<Void, Never>
    }

    private let operation: Operation
    private let delivery: Delivery
    private var pendingByKey: [Key: PendingWork] = [:]
    private var workersByKey: [Key: Worker] = [:]

    init(operation: @escaping Operation, delivery: @escaping Delivery) {
        self.operation = operation
        self.delivery = delivery
    }

    deinit {
        workersByKey.values.forEach { $0.task.cancel() }
    }

    var activeWorkerCount: Int {
        workersByKey.count
    }

    var pendingCount: Int {
        pendingByKey.count
    }

    func schedule(_ input: Input, for key: Key) {
        pendingByKey[key] = PendingWork(input: input)
        guard workersByKey[key] == nil else { return }
        startWorker(for: key)
    }

    func cancel(for key: Key) {
        pendingByKey.removeValue(forKey: key)
        workersByKey.removeValue(forKey: key)?.task.cancel()
    }

    func cancelAll() {
        let tasks = workersByKey.values.map(\.task)
        pendingByKey.removeAll(keepingCapacity: false)
        workersByKey.removeAll(keepingCapacity: false)
        tasks.forEach { $0.cancel() }
    }

    private func startWorker(for key: Key) {
        let workerID = UUID()
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let work = self?.takePendingWork(for: key, workerID: workerID),
                      let operation = self?.operation
                else {
                    break
                }

                do {
                    let output = try await operation(work.input)
                    guard !Task.isCancelled else { break }
                    self?.deliverIfCurrent(
                        output,
                        for: key,
                        work: work,
                        workerID: workerID
                    )
                } catch {
                    // A newer pending request still gets its turn after a failed or cancelled one.
                }
            }
            self?.finishWorker(for: key, workerID: workerID)
        }
        workersByKey[key] = Worker(id: workerID, task: task)
    }

    private func takePendingWork(for key: Key, workerID: UUID) -> PendingWork? {
        guard workersByKey[key]?.id == workerID else { return nil }
        return pendingByKey.removeValue(forKey: key)
    }

    private func deliverIfCurrent(
        _ output: Output,
        for key: Key,
        work: PendingWork,
        workerID: UUID
    ) {
        guard workersByKey[key]?.id == workerID,
              pendingByKey[key] == nil
        else {
            return
        }
        delivery(work.input, output)
    }

    private func finishWorker(for key: Key, workerID: UUID) {
        guard workersByKey[key]?.id == workerID else { return }
        workersByKey.removeValue(forKey: key)
        if pendingByKey[key] != nil {
            startWorker(for: key)
        }
    }
}
