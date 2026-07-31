import Foundation

/// A single model turn exceeded the wall-clock budget without completing an action.
///
/// The live failure this guards (F20): on a trivial 13-file folder-sort, a reasoner model made two
/// real tool calls and then streamed 27k log lines of pure "thinking" — classifying hundreds of
/// files that did not exist — never emitting another action until the process-level timeout killed
/// the run 25 minutes later. No terminal `.say` ever happened, so the promised-work/deferral
/// guards (which inspect terminal says) cannot see this shape; the defense has to live on the
/// stream clock itself.
struct AgentTurnDeadlineExceededError: Error, CustomStringConvertible {
    let seconds: TimeInterval

    var description: String {
        "The model spent more than \(Int(seconds))s on one turn without completing an action."
    }
}

enum AgentTurnDeadline {
    /// Wrap a streaming response so it throws `AgentTurnDeadlineExceededError` if the WHOLE turn
    /// (first token to completed action) runs past `seconds`. Elements pass through untouched
    /// before the deadline; cancellation of the consumer tears down both inner tasks.
    ///
    /// The clock covers the entire turn rather than a per-chunk gap deliberately: a spiraling
    /// reasoner streams steadily (no idle gap ever fires), it just never stops.
    static func enforcing<Element: Sendable>(
        seconds: TimeInterval,
        on stream: AsyncThrowingStream<Element, Error>
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let relay = Task {
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for try await element in stream {
                                continuation.yield(element)
                            }
                        }
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
                            throw AgentTurnDeadlineExceededError(seconds: seconds)
                        }
                        // First child to finish decides: normal stream completion returns, the
                        // deadline (or a stream error) throws. Either way the loser is cancelled.
                        try await group.next()
                        group.cancelAll()
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
    }

    /// The bounded corrective nudge for a deadline overrun — the same recovery family as the
    /// malformed-action correction: one user-role message, then a fresh sample.
    static let correctionPrompt = """
    You spent the whole turn reasoning without emitting an action. Stop planning. Base your next \
    step ONLY on tool output you have actually received in this conversation — do not imagine \
    files, data, or state you have not observed. Respond now with exactly one JSON action object \
    (a tool call for the next concrete step, or a final "say" if the work is genuinely done).
    """
}
