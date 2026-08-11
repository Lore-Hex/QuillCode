import Foundation
import QuillCodeCore

/// Keeps model execution independent from main-actor rendering while retaining only the newest
/// pending snapshot. The final run result remains authoritative when the send completes.
struct WorkspaceAgentProgressRelay: Sendable {
    private let continuation: AsyncStream<ChatThread>.Continuation
    private let consumerTask: Task<Void, Never>

    init(
        consumer: @escaping @MainActor @Sendable (ChatThread) async -> Void
    ) {
        let (stream, continuation) = AsyncStream<ChatThread>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.continuation = continuation
        self.consumerTask = Task { @MainActor in
            for await thread in stream {
                guard !Task.isCancelled else { break }
                await consumer(thread)
            }
        }
    }

    func publish(_ thread: ChatThread) {
        continuation.yield(thread)
    }

    func finish() {
        continuation.finish()
    }

    func cancel() {
        continuation.finish()
        consumerTask.cancel()
    }

    func waitUntilFinished() async {
        await consumerTask.value
    }
}
