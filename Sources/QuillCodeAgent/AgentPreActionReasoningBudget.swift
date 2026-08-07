import Foundation

/// A model exhausted the bounded reasoning budget before emitting any action JSON.
struct AgentPreActionReasoningBudgetExceededError: Error, CustomStringConvertible {
    let maximumCharacters: Int

    var description: String {
        "The model emitted more than \(maximumCharacters) reasoning characters before starting an action."
    }
}

enum AgentPreActionReasoningBudget {
    /// Stops a continuously reasoning stream before it consumes the whole provider completion
    /// budget. Once action text starts, the guard gets out of the way and the normal parser owns
    /// completion. Providers may send reasoning as deltas or as growing snapshots, so both shapes
    /// are counted without double-charging snapshots.
    static func enforcing(
        maximumCharacters: Int,
        on stream: AsyncThrowingStream<AgentTextStreamEvent, Error>
    ) -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let relay = Task {
                do {
                    var reasoning = ""
                    var lastFragment = ""
                    var actionStarted = false

                    for try await event in stream {
                        try Task.checkCancellation()
                        switch event {
                        case .text(let fragment) where !fragment.isEmpty:
                            actionStarted = true
                        case .reasoning(let fragment) where !actionStarted && !fragment.isEmpty:
                            if fragment != lastFragment {
                                if !reasoning.isEmpty,
                                   fragment.hasPrefix(reasoning),
                                   fragment.count > reasoning.count {
                                    reasoning = fragment
                                } else {
                                    reasoning.append(fragment)
                                }
                                lastFragment = fragment
                            }
                            if reasoning.count > maximumCharacters {
                                throw AgentPreActionReasoningBudgetExceededError(
                                    maximumCharacters: maximumCharacters
                                )
                            }
                        default:
                            break
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
    }

    static let correctionPrompt = """
    You used the available reasoning budget without starting an action. Stop planning. Do not scan \
    or inventory the workspace unless the user named it as a source. If required business facts \
    are missing, ask one focused question; otherwise use explicit assumptions and placeholders. \
    Respond now with exactly one JSON action object (a concrete tool call, or a final "say").
    """
}
