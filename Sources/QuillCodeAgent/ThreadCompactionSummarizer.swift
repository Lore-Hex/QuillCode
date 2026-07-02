import Foundation
import QuillCodeCore

/// Produces the durable summary text that replaces the compacted-away turns of a thread. Injected into
/// `ThreadCompactor` so the run-loop compaction path can be driven by a deterministic mock in tests and
/// by a cheap auxiliary model in production, without the compactor knowing which.
public protocol ThreadCompactionSummarizing: Sendable {
    /// Summarize the older turns into a compact continuation summary. `recentMessages` is passed for
    /// context only — it is preserved verbatim by the caller and MUST NOT be dropped or restated as if
    /// already done. Throwing signals the summarizer failed; the compactor then falls back to a
    /// deterministic summary so a run never dies because the summary model was unreachable.
    func summarize(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) async throws -> String
}

/// The always-available fallback: a deterministic, model-free summary built from the dropped turns.
/// Used when no summary model is configured, and as the safety net when the model summarizer throws —
/// so compaction (and therefore the run) proceeds regardless.
public struct DeterministicThreadCompactionSummarizer: ThreadCompactionSummarizing {
    public init() {}

    public func summarize(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) async throws -> String {
        ThreadCompactionSummaryText.deterministic(
            sourceTitle: sourceTitle,
            olderMessages: olderMessages,
            recentMessages: recentMessages
        )
    }
}

/// Summarizes via a cheap auxiliary LLM. Mirrors the app-layer `LLMWorkspaceContextSummaryGenerator`
/// but lives in the agent layer so the run loop can compact-and-resume without depending on the app
/// target. Best-effort by construction: the client is expected to already be caching-disabled and
/// aux-model-retargeted by the caller (see `ThreadCompactor.llmBacked`), and any failure surfaces as a
/// throw the compactor absorbs into the deterministic fallback.
public struct LLMThreadCompactionSummarizer: ThreadCompactionSummarizing {
    public var llm: any LLMClient

    public init(llm: any LLMClient) {
        self.llm = llm
    }

    public func summarize(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) async throws -> String {
        let prompt = ThreadCompactionSummaryText.prompt(
            sourceTitle: sourceTitle,
            olderMessages: olderMessages,
            recentMessages: recentMessages
        )
        let action = try await llm.nextAction(
            thread: ChatThread(title: "Context compaction"),
            userMessage: prompt,
            tools: []
        )
        guard case .say(let text) = action,
              let summary = ThreadCompactionSummaryText.sanitized(text)
        else {
            throw ThreadCompactionSummarizerError.invalidModelSummary
        }
        return summary
    }
}

enum ThreadCompactionSummarizerError: Error, CustomStringConvertible {
    case invalidModelSummary

    var description: String {
        switch self {
        case .invalidModelSummary:
            return "Compaction summary model did not return a valid summary."
        }
    }
}
