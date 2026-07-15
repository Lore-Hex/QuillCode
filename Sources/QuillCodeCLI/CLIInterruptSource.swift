import CQuillPTY
import Dispatch
import Foundation

protocol CLIInterruptSource: Sendable {
    func makeInterruptStream() -> AsyncStream<Void>
}

struct ProcessCLIInterruptSource: CLIInterruptSource {
    func makeInterruptStream() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let lifetime = DispatchSignalLifetime(
                signalNumber: Int32(cquill_signal_interrupt()),
                continuation: continuation
            )
            continuation.onTermination = { @Sendable _ in lifetime.cancel() }
            lifetime.start()
        }
    }
}

/// Test and embedding boundary for command runners that must not modify process-global signal state.
struct InactiveCLIInterruptSource: CLIInterruptSource {
    func makeInterruptStream() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}

private final class DispatchSignalLifetime: @unchecked Sendable {
    private let signalNumber: Int32
    private let continuation: AsyncStream<Void>.Continuation
    private let source: DispatchSourceSignal
    private let lock = NSLock()
    private var isCancelled = false

    init(signalNumber: Int32, continuation: AsyncStream<Void>.Continuation) {
        self.signalNumber = signalNumber
        self.continuation = continuation
        _ = cquill_signal_ignore(signalNumber)
        source = DispatchSource.makeSignalSource(
            signal: signalNumber,
            queue: DispatchQueue(label: "com.lorehex.quillcode.cli-interrupt")
        )
        source.setEventHandler { [weak self] in self?.interrupt() }
        source.setCancelHandler { [signalNumber] in
            _ = cquill_signal_restore_default(signalNumber)
        }
    }

    func start() {
        source.resume()
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        lock.unlock()
        source.cancel()
    }

    private func interrupt() {
        continuation.yield()
        continuation.finish()
    }
}

func runUntilInterrupted<Value: Sendable>(
    source: any CLIInterruptSource,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            var iterator = source.makeInterruptStream().makeAsyncIterator()
            guard await iterator.next() != nil else {
                try Task.checkCancellation()
                throw CancellationError()
            }
            throw CancellationError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw CancellationError() }
        return result
    }
}
