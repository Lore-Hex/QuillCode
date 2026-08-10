import Foundation

enum AgentReasoningBudgetPhase: Sendable {
    case startup
    case synthesis
    case checkpoint
    case correction
    case boundedFinalization
}

/// A model exhausted the bounded reasoning budget before emitting the run's first action JSON.
struct AgentPreActionReasoningBudgetExceededError: Error, CustomStringConvertible {
    let maximumCharacters: Int

    var description: String {
        "The model emitted more than \(maximumCharacters) reasoning characters before starting an action."
    }
}

/// The provider completed a stream after emitting reasoning but never started action JSON.
/// This is semantically different from a zero-token transport response: replaying the same turn
/// invites the reasoner to consume its completion budget again, so the resolver must re-prompt it
/// through the bounded action-only correction path.
struct AgentReasoningOnlyResponseError: Error, CustomStringConvertible {
    var description: String {
        "The model finished reasoning without returning an action."
    }
}

enum AgentPreActionReasoningBudget {
    /// DeepSeek V4 Flash has returned reasoning-only completions at roughly 2,200 output tokens even
    /// when the route receives `reasoning_effort: none`. Keep enough room for a grounded decision,
    /// but interrupt before the provider ceiling can consume the entire action turn.
    static let deepSeekV4Flash0731CharacterLimit = 6_000
    /// Grounded synthesis is materially different from startup routing. DeepSeek V4 Flash often
    /// reaches the action only after roughly 2,000 reasoning tokens even with reasoning disabled at
    /// the route. Give synthesis and action-only recovery one larger, still-bounded window while
    /// keeping startup, checkpoint verification, and every other model on their existing limits.
    static let deepSeekV4Flash0731SynthesisCharacterLimit = 12_000

    static func effectiveMaximumCharacters(
        configured: Int,
        modelID: String,
        phase: AgentReasoningBudgetPhase
    ) -> Int {
        guard modelID == TrustedRouterChatParameters.deepSeekV4Flash0731Model else {
            return configured
        }
        let providerLimit = switch phase {
        case .startup, .checkpoint:
            deepSeekV4Flash0731CharacterLimit
        case .synthesis, .correction, .boundedFinalization:
            deepSeekV4Flash0731SynthesisCharacterLimit
        }
        return min(configured, providerLimit)
    }

    /// Stops a continuously reasoning startup stream before it consumes the whole provider
    /// completion budget. The runner applies this only until the run emits its first action; once
    /// action text starts, the normal parser and the run's other bounds own completion. Providers
    /// may send reasoning as deltas or as growing snapshots, so both shapes are counted without
    /// double-charging snapshots.
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
    You used the available reasoning budget without starting an action. Stop planning and do not \
    narrate. Use the evidence and tool results already in the thread. If the user named a text \
    deliverable that has not been written, write the best current evidence checkpoint to that exact \
    path now; otherwise emit the single concrete tool action that advances the latest unfinished \
    step. Do not restart broad research, ask the user, or insert placeholders when an available tool \
    can make progress. Respond now with exactly one JSON action object (a concrete tool call, or a \
    final "say" only when the requested work is actually complete or irrecoverably blocked).
    """

    static func recoveryPrompt(preserving priorCorrection: String?) -> String {
        guard let priorCorrection,
              !priorCorrection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return correctionPrompt
        }
        return """
        You used the available reasoning budget without starting an action. The immediately preceding \
        corrective instruction remains authoritative; do not replace, reinterpret, or defer it. Stop \
        planning and execute its concrete action now using the evidence already in the thread. If that \
        instruction names a tool or exact output path, your next action MUST use that tool and exact path. \
        Do not resume research, delegate more work, ask the user, narrate, or return a final answer instead \
        of the required action. Respond now with exactly one JSON action object.
        """
    }
}
