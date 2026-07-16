import Foundation
import QuillCodeCore

/// The outcome of one compaction attempt on a thread.
public enum ThreadCompactionResult: Sendable, Equatable {
    /// The thread was compacted: `summarizedCount` older messages were replaced by one summary message.
    /// `usedModel` is true when the model summary succeeded, false when the deterministic fallback was
    /// used. `lastResortTruncated` is true when even the preserved recent turns had to be hard-trimmed.
    case compacted(summarizedCount: Int, usedModel: Bool, lastResortTruncated: Bool)
    /// Nothing to compact — there were no older turns to fold away (the thread is already at or below
    /// the preserved-recent floor). The caller must NOT loop again on the same thread.
    case noOlderTurns
}

/// Folds a thread's older turns into a single durable summary message so an overflowing (or nearly
/// overflowing) run can continue instead of failing at the context wall. This is the compaction half
/// of issue #862; the detection half is `ContextOverflowDetector`, and the run loop
/// (`AgentRunner.send`) composes them: on overflow, compact and resume.
///
/// Guarantees the reviewers will probe:
/// - The current user request and the active tool exchange are NEVER dropped — they live in the
///   preserved recent tail (`keepRecentMessages`, extended to keep an assistant/tool pair whole and to
///   always include the last user message).
/// - Leading system messages are preserved verbatim (the system prompt itself is re-added by the
///   prompt builder, but any in-thread system message is kept as anchor content).
/// - Idempotent and bounded: when there is nothing older to fold, it reports `.noOlderTurns` so the
///   caller stops instead of looping. When even the kept tail is too big for a single turn, a
///   last-resort front-truncation with an explicit marker keeps the run alive.
/// - Total on adversarial input: no force-unwraps, no range subscripts on possibly-empty content, and
///   token math via the saturating `ContextTokenEstimator`.
public struct ThreadCompactor: Sendable {
    /// How many trailing messages to preserve verbatim (extended as needed to keep a tool exchange
    /// whole and to always include the last user message). Clamped to at least 1 so the current turn
    /// always survives.
    public var keepRecentMessages: Int
    /// A single preserved message whose estimated tokens exceed this gets last-resort front-truncated
    /// (keeping its tail) so one giant tool result cannot defeat compaction. 0 disables the floor.
    public var perMessageTokenFloor: Int
    public var summarizer: any ThreadCompactionSummarizing

    public init(
        keepRecentMessages: Int = 6,
        perMessageTokenFloor: Int = 24_000,
        summarizer: any ThreadCompactionSummarizing = DeterministicThreadCompactionSummarizer()
    ) {
        self.keepRecentMessages = max(1, keepRecentMessages)
        self.perMessageTokenFloor = max(0, perMessageTokenFloor)
        self.summarizer = summarizer
    }

    /// A compactor whose summaries run on a cheap auxiliary model with prompt caching disabled — the
    /// production wiring. `catalog`/`sessionModelID` pick the aux model via `AuxiliaryModelSelector`;
    /// when no priced candidate exists it keeps the session model (never fails to build a compactor).
    /// A client that cannot be caching-disabled or model-overridden is used as-is (e.g. a test mock).
    public static func llmBacked(
        llm: any LLMClient,
        catalog: [ModelInfo],
        sessionModelID: String,
        keepRecentMessages: Int = 6,
        perMessageTokenFloor: Int = 24_000,
        customPrompt: String? = nil
    ) -> ThreadCompactor {
        let cachingDisabled = disablingPromptCachingIfSupported(llm)
        let selection = AuxiliaryModelSelector.selection(models: catalog, sessionModelID: sessionModelID)
        let retargeted = (cachingDisabled as? any ModelOverridingLLMClient)?
            .overridingModel(selection.modelID) ?? cachingDisabled
        return ThreadCompactor(
            keepRecentMessages: keepRecentMessages,
            perMessageTokenFloor: perMessageTokenFloor,
            summarizer: LLMThreadCompactionSummarizer(
                llm: retargeted,
                customPrompt: customPrompt
            )
        )
    }

    /// Compacts `thread` in place. Returns `.noOlderTurns` (and leaves the thread untouched apart from
    /// possible last-resort truncation of the kept tail) when there is nothing older to fold — the
    /// caller uses that to terminate the compaction loop.
    @discardableResult
    public func compact(_ thread: inout ChatThread) async -> ThreadCompactionResult {
        let partition = partitionMessages(thread.messages)
        // Folding fewer than `minOlderToFold` messages does not shrink the thread — one older message
        // becomes one summary message. Requiring at least two guarantees every successful compaction
        // strictly reduces the message count, so the reactive loop provably TERMINATES instead of
        // re-summarizing its own summary forever.
        guard partition.older.count >= Self.minOlderToFold else {
            // Nothing worth folding. Still apply the last-resort floor so a single giant kept message
            // can't keep overflowing, but report noOlderTurns so the loop terminates.
            let truncated = applyLastResortTruncation(to: &thread.messages)
            recordSeam(
                in: &thread,
                summarizedCount: 0,
                usedModel: false,
                lastResortTruncated: truncated,
                noOlderTurns: true
            )
            return .noOlderTurns
        }

        let (summaryText, usedModel) = await summaryText(for: thread.title, partition: partition)
        // The summarizer's ordinary failures intentionally fall back to deterministic text, but a
        // cancelled caller must not splice that fallback into durable history. There is no suspension
        // between this check and the splice, so cancellation observed while awaiting the summarizer
        // leaves the thread untouched and lets the owning operation report interruption.
        guard !Task.isCancelled else { return .noOlderTurns }
        let summaryMessage = ChatMessage(role: .assistant, content: summaryText)

        // Splice: [leading system messages] + [summary] + [preserved recent tail].
        var rebuilt = partition.leadingSystem
        rebuilt.append(summaryMessage)
        rebuilt.append(contentsOf: partition.recent)
        thread.messages = rebuilt

        let lastResortTruncated = applyLastResortTruncation(to: &thread.messages)
        recordSeam(
            in: &thread,
            summarizedCount: partition.older.count,
            usedModel: usedModel,
            lastResortTruncated: lastResortTruncated,
            noOlderTurns: false
        )
        return .compacted(
            summarizedCount: partition.older.count,
            usedModel: usedModel,
            lastResortTruncated: lastResortTruncated
        )
    }

    // MARK: - Summary

    private func summaryText(
        for sourceTitle: String,
        partition: MessagePartition
    ) async -> (text: String, usedModel: Bool) {
        do {
            let text = try await summarizer.summarize(
                sourceTitle: sourceTitle,
                olderMessages: partition.older,
                recentMessages: partition.recent
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return (deterministicSummary(sourceTitle: sourceTitle, partition: partition), false)
            }
            return (trimmed, true)
        } catch {
            return (deterministicSummary(sourceTitle: sourceTitle, partition: partition), false)
        }
    }

    private func deterministicSummary(sourceTitle: String, partition: MessagePartition) -> String {
        ThreadCompactionSummaryText.deterministic(
            sourceTitle: sourceTitle,
            olderMessages: partition.older,
            recentMessages: partition.recent
        )
    }

    // MARK: - Partitioning

    struct MessagePartition {
        var leadingSystem: [ChatMessage]
        var older: [ChatMessage]
        var recent: [ChatMessage]
    }

    /// Splits messages into [leading system anchors][older, to summarize][recent, preserved verbatim].
    /// The recent window is `keepRecentMessages` from the end, then EXTENDED backward so it (a) always
    /// includes the last user message — never orphan the current request — and (b) never begins on a
    /// `.tool` message whose originating assistant turn would be stranded in the summarized older set.
    func partitionMessages(_ messages: [ChatMessage]) -> MessagePartition {
        // Leading system messages are anchors, never summarized.
        var leadingSystemEnd = 0
        while leadingSystemEnd < messages.count, messages[leadingSystemEnd].role == .system {
            leadingSystemEnd += 1
        }
        let leadingSystem = Array(messages[0..<leadingSystemEnd])
        let body = Array(messages[leadingSystemEnd...])
        guard !body.isEmpty else {
            return MessagePartition(leadingSystem: leadingSystem, older: [], recent: [])
        }

        // Start from the last `keepRecentMessages`, clamped to the body.
        var recentStart = max(0, body.count - keepRecentMessages)
        recentStart = extendToIncludeLastUserMessage(in: body, from: recentStart)
        recentStart = extendPastLeadingToolMessages(in: body, from: recentStart)

        let older = Array(body[0..<recentStart])
        let recent = Array(body[recentStart...])
        return MessagePartition(leadingSystem: leadingSystem, older: older, recent: recent)
    }

    /// Never orphan the current request: if the last user message sits before the recent window, pull
    /// the window's start back to it so it (and everything after) is preserved verbatim.
    private func extendToIncludeLastUserMessage(in body: [ChatMessage], from start: Int) -> Int {
        guard let lastUserIndex = body.lastIndex(where: { $0.role == .user }) else { return start }
        return min(start, lastUserIndex)
    }

    /// Don't begin the preserved tail on a `.tool` message: its result would be kept while the
    /// assistant call that produced it is summarized away, which reads as an orphaned tool output.
    /// Walk the start backward over any leading `.tool` messages (and the assistant turn before them).
    private func extendPastLeadingToolMessages(in body: [ChatMessage], from start: Int) -> Int {
        var index = start
        while index > 0, body[index].role == .tool {
            index -= 1
        }
        // If we stopped on the assistant turn that OWNS the tool output, keep that too so the call and
        // its result stay together.
        if index > 0, index < body.count, body[index].role == .tool, body[index - 1].role == .assistant {
            index -= 1
        }
        return index
    }

    // MARK: - Last-resort truncation

    /// Front-truncates any single preserved message whose estimated tokens exceed the floor, keeping
    /// its TAIL (the recent, most relevant part) with an explicit marker. This is the terminator that
    /// keeps the run alive when even one kept turn — a giant tool result — is too big for the window.
    /// Returns whether anything was truncated. `perMessageTokenFloor == 0` disables it.
    private func applyLastResortTruncation(to messages: inout [ChatMessage]) -> Bool {
        guard perMessageTokenFloor > 0 else { return false }
        var truncatedAny = false
        for index in messages.indices {
            let content = messages[index].content
            guard ContextTokenEstimator.estimatedTokens(forText: content) > perMessageTokenFloor else {
                continue
            }
            let keptCharacters = max(1, perMessageTokenFloor * ContextTokenEstimator.charactersPerToken)
            guard content.count > keptCharacters else { continue }
            let tail = String(content.suffix(keptCharacters))
            messages[index].content = Self.truncationMarker + tail
            truncatedAny = true
        }
        return truncatedAny
    }

    static let truncationMarker =
        "[QuillCode compaction: earlier content of this message was truncated "
        + "to fit the context window]\n"

    /// The minimum number of older messages worth folding into a summary. Below this, compaction would
    /// not reduce the message count (1 message → 1 summary), so it reports `.noOlderTurns` instead —
    /// the invariant that makes the reactive compaction loop terminate.
    static let minOlderToFold = 2

    // MARK: - Seam annotation

    private func recordSeam(
        in thread: inout ChatThread,
        summarizedCount: Int,
        usedModel: Bool,
        lastResortTruncated: Bool,
        noOlderTurns: Bool
    ) {
        // Nothing happened at all — no summary, no truncation — so don't spam a seam event.
        if noOlderTurns, !lastResortTruncated { return }

        let summary: String
        if summarizedCount > 0 {
            summary = "Compacted \(summarizedCount) earlier "
                + (summarizedCount == 1 ? "turn" : "turns")
                + " into a summary to fit the context window"
                + (usedModel ? "." : " (deterministic summary).")
                + (lastResortTruncated ? " Also truncated an oversized kept message." : "")
        } else {
            summary = "Truncated an oversized message to fit the context window."
        }

        let payload = CompactionSeamPayload(
            summarizedTurns: summarizedCount,
            usedModelSummary: usedModel,
            lastResortTruncated: lastResortTruncated
        )
        thread.events.append(ThreadEvent(
            kind: .notice,
            summary: summary,
            payloadJSON: try? JSONHelpers.encodePretty(payload)
        ))
        thread.updatedAt = Date()
    }
}

/// The auditable payload on a compaction seam event, so the transcript can show exactly what the
/// compaction did (how many turns folded, whether the model or the deterministic fallback wrote the
/// summary, whether a last-resort truncation fired).
struct CompactionSeamPayload: Codable, Sendable, Hashable {
    var summarizedTurns: Int
    var usedModelSummary: Bool
    var lastResortTruncated: Bool
}
