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

/// Raised when a caller requests explicit compaction from a runner that was intentionally composed
/// without a compaction policy. Production desktop and CLI compositions always provide one; keeping
/// the failure typed makes incomplete embeddings fail honestly instead of silently reporting success.
public struct ManualCompactionUnavailableError: LocalizedError, Sendable {
    public init() {}

    public var errorDescription: String? {
        "Manual thread compaction is unavailable because this agent runner has no compaction policy."
    }
}

extension AgentRunner {
    /// Runs one explicit compaction through the same hooks, summarizer, progress, and persistence
    /// boundary used by proactive and overflow recovery. The caller owns persistence of the returned
    /// thread snapshot; progress is emitted after every durable mutation, including hook notices.
    @discardableResult
    public func compactManually(
        thread: inout ChatThread,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> ThreadCompactionResult {
        guard let compaction else { throw ManualCompactionUnavailableError() }
        return try await compact(
            thread: &thread,
            using: compaction.compactor,
            trigger: .manual,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        )
    }

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

        try await compactProactivelyIfNeeded(
            thread: &thread,
            compaction: compaction,
            workspaceRoot: workspaceRoot,
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
                // Only a recognized context overflow is compactable; everything else propagates
                // untouched so the retry/terminal paths keep their existing behavior. Crucially, the
                // detector is status-gated: a rate-limit (429, even one whose body says "too many
                // tokens") or a transient 5xx is NOT an overflow, so it re-throws here — after
                // RetryingLLMClient has exhausted its retries — surfacing the real cause instead of
                // destroying turns with a compaction it can never satisfy. Also excluded: transport
                // blips, auth, cancellation, and a benign 4xx with no context marker.
                guard ContextOverflowDetector.isContextOverflow(error) else { throw error }
                try Task.checkCancellation()

                guard rounds < compaction.maxRoundsPerCall else {
                    throw ContextOverflowUnresolvedError(rounds: rounds, underlying: error)
                }
                rounds += 1
                let result = try await compact(
                    thread: &thread,
                    using: compaction.compactor,
                    trigger: .auto,
                    workspaceRoot: workspaceRoot,
                    onProgress: onProgress
                )
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
    /// after a fixed number of rounds instead of looping. Compactor failures remain best-effort, but
    /// an explicit trusted PreCompact/PostCompact stop propagates and ends the active turn.
    private func compactProactivelyIfNeeded(
        thread: inout ChatThread,
        compaction: AgentCompactionPolicy,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws {
        guard compaction.proactiveTokenLimit > 0 else { return }
        var rounds = 0
        while rounds < compaction.maxRoundsPerCall {
            let estimate = ContextTokenEstimator.estimatedTokens(for: thread)
            guard ContextOverflowDetector.proactiveSignal(
                estimatedTokens: estimate,
                limit: compaction.proactiveTokenLimit
            ) != nil else { return }
            rounds += 1
            let result = try await compact(
                thread: &thread,
                using: compaction.compactor,
                trigger: .auto,
                workspaceRoot: workspaceRoot,
                onProgress: onProgress
            )
            if case .noOlderTurns = result { return }
        }
    }

    private func compact(
        thread: inout ChatThread,
        using compactor: ThreadCompactor,
        trigger: AgentCompactionTrigger,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> ThreadCompactionResult {
        try await runCompactionHook(
            preCompactHook,
            stage: .before,
            trigger: trigger,
            thread: &thread,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        )

        let result = await compactor.compact(&thread)
        try Task.checkCancellation()
        await onProgress?(thread)
        guard case .compacted = result else { return result }

        try await runCompactionHook(
            postCompactHook,
            stage: .after,
            trigger: trigger,
            thread: &thread,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        )
        return result
    }

    private func runCompactionHook(
        _ hook: AgentCompactionHook?,
        stage: AgentCompactionHookStage,
        trigger: AgentCompactionTrigger,
        thread: inout ChatThread,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws {
        guard let hook else { return }
        let outcome: AgentCompactionHookOutcome
        do {
            outcome = try await hook(trigger, thread, workspaceRoot)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            appendCompactionNotice(
                "Compaction hook warning: \(error.localizedDescription). Compaction continued.",
                to: &thread
            )
            await onProgress?(thread)
            return
        }

        for notice in outcome.notices {
            appendCompactionNotice(notice, to: &thread)
        }
        if !outcome.notices.isEmpty {
            await onProgress?(thread)
        }
        guard outcome.continues else {
            throw AgentCompactionHookStoppedError(
                trigger: trigger,
                stage: stage,
                reason: outcome.stopReason ?? "A trusted compaction hook stopped this operation."
            )
        }
    }

    private func appendCompactionNotice(_ notice: String, to thread: inout ChatThread) {
        let bounded = String(
            notice
                .replacingOccurrences(of: "\0", with: "")
                .prefix(4_096)
        )
        guard !bounded.isEmpty else { return }
        thread.events.append(ThreadEvent(kind: .notice, summary: bounded))
        thread.updatedAt = Date()
    }
}
