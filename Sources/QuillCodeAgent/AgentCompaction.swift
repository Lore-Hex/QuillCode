import Foundation
import QuillCodeCore

/// How the run loop compacts and resumes when the context window overflows (issue #862). Bundles the
/// compactor with the two bounds that make the overflow → compact → resume path provably terminate:
/// a proactive token threshold (compact BEFORE the wall) and a hard cap on compaction rounds per model
/// call (after which the run gives up honestly rather than looping forever).
public struct AgentCompactionPolicy: Sendable {
    public var compactor: ThreadCompactor
    /// Estimated prompt-token count at or above which the loop compacts proactively, before issuing the
    /// model call. 0 disables proactive compaction (only reactive, on an overflow error).
    public var proactiveTokenLimit: Int
    /// The maximum number of compaction rounds attempted for a SINGLE model call before the run gives
    /// up. Bounds the reactive loop so a prompt that still overflows after compaction (or a summarizer
    /// that cannot shrink it) cannot spin forever. Clamped to at least 1.
    public var maxRoundsPerCall: Int

    public init(
        compactor: ThreadCompactor,
        proactiveTokenLimit: Int = 0,
        maxRoundsPerCall: Int = 3
    ) {
        self.compactor = compactor
        self.proactiveTokenLimit = max(0, proactiveTokenLimit)
        self.maxRoundsPerCall = max(1, maxRoundsPerCall)
    }
}

/// Raised when the run loop exhausted its compaction budget and the context STILL overflows — there is
/// nothing left to safely fold away. Carries the round count so the surfaced diagnostic is honest about
/// how hard the loop tried. This is the terminator: the run fails with a clear reason instead of
/// looping, and instead of the raw provider error that would confuse an unattended operator.
public struct ContextOverflowUnresolvedError: Error, CustomStringConvertible {
    public var rounds: Int
    public var underlying: any Error

    public init(rounds: Int, underlying: any Error) {
        self.rounds = rounds
        self.underlying = underlying
    }

    public var description: String {
        "The context window overflowed and could not be reduced by compaction after \(rounds) "
            + "\(rounds == 1 ? "round" : "rounds"); the run was stopped. Underlying error: "
            + "\(String(describing: underlying))"
    }
}

extension AgentRunner {
    /// Obtains the next action, compacting-and-resuming on a context overflow instead of failing the
    /// run. When `compaction` is nil this is a straight pass-through to `nextAction`, so a runner
    /// without a policy behaves exactly as before.
    ///
    /// Two ways it engages, both bounded:
    /// - PROACTIVE: if the assembled thread is already estimated over the token threshold, compact
    ///   once before the call (bounded by `maxRoundsPerCall`), so a growing thread is trimmed before it
    ///   fails a round-trip.
    /// - REACTIVE: if the call throws a `ContextOverflowDetector`-recognized error, compact and retry,
    ///   up to `maxRoundsPerCall`. If a round reports `.noOlderTurns` (nothing left to fold) or the cap
    ///   is reached, surface `ContextOverflowUnresolvedError` — terminate, never loop.
    func nextActionCompactingOnOverflow(
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        guard let compaction else {
            return try await nextAction(
                thread: &thread,
                userMessage: userMessage,
                tools: tools,
                workspaceRoot: workspaceRoot,
                onProgress: onProgress
            )
        }

        await compactProactivelyIfNeeded(
            thread: &thread,
            compaction: compaction,
            onProgress: onProgress
        )

        var rounds = 0
        while true {
            do {
                return try await nextAction(
                    thread: &thread,
                    userMessage: userMessage,
                    tools: tools,
                    workspaceRoot: workspaceRoot,
                    onProgress: onProgress
                )
            } catch {
                // Only a recognized context overflow is compactable; everything else (transport,
                // auth, cancellation, a benign 413 with no context marker) propagates untouched so
                // the retry/terminal paths keep their existing behavior.
                guard ContextOverflowDetector.isContextOverflow(error) else { throw error }
                try Task.checkCancellation()

                guard rounds < compaction.maxRoundsPerCall else {
                    throw ContextOverflowUnresolvedError(rounds: rounds, underlying: error)
                }
                rounds += 1
                let result = await compaction.compactor.compact(&thread)
                await onProgress?(thread)
                // Nothing left to fold away: compacting again would be a no-op, so stop here with a
                // clear diagnostic rather than spinning to the round cap.
                if case .noOlderTurns = result {
                    throw ContextOverflowUnresolvedError(rounds: rounds, underlying: error)
                }
            }
        }
    }

    /// Compacts before the call when the thread's estimated tokens cross the proactive threshold.
    /// Bounded by `maxRoundsPerCall` and by `.noOlderTurns`, so even a thread of giant messages settles
    /// after a fixed number of rounds instead of looping. Never throws — proactive compaction is
    /// best-effort; if it cannot get under the threshold, the model call still runs and the reactive
    /// path handles any resulting overflow.
    private func compactProactivelyIfNeeded(
        thread: inout ChatThread,
        compaction: AgentCompactionPolicy,
        onProgress: AgentRunProgressHandler?
    ) async {
        guard compaction.proactiveTokenLimit > 0 else { return }
        var rounds = 0
        while rounds < compaction.maxRoundsPerCall {
            let estimate = ContextTokenEstimator.estimatedTokens(for: thread)
            guard ContextOverflowDetector.proactiveSignal(
                estimatedTokens: estimate,
                limit: compaction.proactiveTokenLimit
            ) != nil else { return }
            rounds += 1
            let result = await compaction.compactor.compact(&thread)
            await onProgress?(thread)
            if case .noOlderTurns = result { return }
        }
    }
}
