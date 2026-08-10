import Foundation

/// A shell reader must never outrun its UI or agent consumer into an unbounded `AsyncStream`
/// allocation. Keeping the newest events preserves interactive freshness, and a terminal
/// `.finished` event is necessarily retained because it is the final yielded value.
enum ShellProcessEventStream {
    static let maximumPendingEventCount = 64

    static func makeStream() -> (
        stream: AsyncStream<ShellProcessEvent>,
        continuation: AsyncStream<ShellProcessEvent>.Continuation
    ) {
        AsyncStream.makeStream(
            of: ShellProcessEvent.self,
            bufferingPolicy: .bufferingNewest(maximumPendingEventCount)
        )
    }
}
