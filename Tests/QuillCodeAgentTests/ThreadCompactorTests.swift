import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// A summarizer that returns a fixed marker string, so a test can assert the summary landed exactly
/// where the older turns were.
private struct FixedSummarizer: ThreadCompactionSummarizing {
    var text: String
    func summarize(sourceTitle: String, olderMessages: [ChatMessage], recentMessages: [ChatMessage]) async throws -> String {
        text
    }
}

/// A summarizer that always throws, to exercise the deterministic fallback.
private struct ThrowingSummarizer: ThreadCompactionSummarizing {
    struct Boom: Error {}
    func summarize(sourceTitle: String, olderMessages: [ChatMessage], recentMessages: [ChatMessage]) async throws -> String {
        throw Boom()
    }
}

/// A summarizer that returns only whitespace, to exercise the empty-summary fallback.
private struct BlankSummarizer: ThreadCompactionSummarizing {
    func summarize(sourceTitle: String, olderMessages: [ChatMessage], recentMessages: [ChatMessage]) async throws -> String {
        "   \n  "
    }
}

final class ThreadCompactorTests: XCTestCase {
    private func thread(_ messages: [ChatMessage], title: String = "Source") -> ChatThread {
        ChatThread(title: title, messages: messages)
    }

    private func conversation(pairs: Int) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        for i in 0..<pairs {
            messages.append(ChatMessage(role: .user, content: "user turn \(i)"))
            messages.append(ChatMessage(role: .assistant, content: "assistant turn \(i)"))
        }
        return messages
    }

    // MARK: - Summarize + splice

    func testCompactSummarizesOlderAndKeepsRecent() async {
        let compactor = ThreadCompactor(
            keepRecentMessages: 4,
            perMessageTokenFloor: 0,
            summarizer: FixedSummarizer(text: "SUMMARY")
        )
        var t = thread(conversation(pairs: 10)) // 20 messages
        let result = await compactor.compact(&t)

        guard case .compacted(let count, let usedModel, let truncated) = result else {
            return XCTFail("expected .compacted, got \(result)")
        }
        XCTAssertEqual(count, 16) // 20 - 4 recent
        XCTAssertTrue(usedModel)
        XCTAssertFalse(truncated)

        // First message is now the summary; the last 4 originals are preserved verbatim.
        XCTAssertEqual(t.messages.first?.content, "SUMMARY")
        XCTAssertEqual(t.messages.first?.role, .assistant)
        XCTAssertEqual(t.messages.count, 5) // summary + 4 recent
        XCTAssertEqual(t.messages.suffix(4).map(\.content), [
            "user turn 8", "assistant turn 8", "user turn 9", "assistant turn 9",
        ])
    }

    func testCompactPreservesLeadingSystemMessages() async {
        let compactor = ThreadCompactor(keepRecentMessages: 2, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var messages = [ChatMessage(role: .system, content: "SYSTEM ANCHOR")]
        messages.append(contentsOf: conversation(pairs: 5))
        var t = thread(messages)
        _ = await compactor.compact(&t)

        XCTAssertEqual(t.messages.first?.role, .system)
        XCTAssertEqual(t.messages.first?.content, "SYSTEM ANCHOR")
        XCTAssertEqual(t.messages[1].content, "SUM") // summary after the system anchor
    }

    // MARK: - Never drop the current user request

    func testCurrentUserRequestNeverDroppedEvenBeyondRecentWindow() async {
        // A long run: the last user message sits well before the recent window, but a trailing tool
        // exchange fills the window. Compaction must pull the window back to keep the user request.
        let compactor = ThreadCompactor(keepRecentMessages: 2, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var messages = conversation(pairs: 5)
        messages.append(ChatMessage(role: .user, content: "THE CURRENT REQUEST"))
        messages.append(ChatMessage(role: .assistant, content: "working on it"))
        messages.append(ChatMessage(role: .tool, content: "tool output 1"))
        messages.append(ChatMessage(role: .tool, content: "tool output 2"))
        var t = thread(messages)
        _ = await compactor.compact(&t)

        XCTAssertTrue(
            t.messages.contains { $0.role == .user && $0.content == "THE CURRENT REQUEST" },
            "the current user request must survive compaction"
        )
    }

    // MARK: - Never orphan an active tool exchange

    func testRecentTailNeverBeginsOnOrphanedToolMessage() async {
        // The window falls right after the last user message so the user-message pullback does not
        // confound this: the tail would begin on a .tool result, and the compactor must walk it back
        // to the assistant call that produced it.
        let compactor = ThreadCompactor(keepRecentMessages: 2, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var messages = conversation(pairs: 5)
        messages.append(ChatMessage(role: .user, content: "do the thing"))
        messages.append(ChatMessage(role: .assistant, content: "calling a tool"))
        messages.append(ChatMessage(role: .tool, content: "tool result A"))
        messages.append(ChatMessage(role: .tool, content: "tool result B"))
        var t = thread(messages)
        _ = await compactor.compact(&t)

        // The first preserved non-summary/non-system message must not be a stranded .tool result.
        let preserved = t.messages.drop { $0.role == .system }.dropFirst() // drop summary
        XCTAssertNotEqual(preserved.first?.role, .tool, "tail must not begin on an orphaned tool message")
        // Both the user request and the assistant tool call are preserved together with their results.
        XCTAssertTrue(preserved.contains { $0.content == "do the thing" })
        XCTAssertTrue(preserved.contains { $0.content == "calling a tool" })
    }

    // MARK: - Deterministic fallback

    func testFallsBackToDeterministicSummaryWhenModelThrows() async {
        let compactor = ThreadCompactor(keepRecentMessages: 2, perMessageTokenFloor: 0,
                                        summarizer: ThrowingSummarizer())
        var t = thread(conversation(pairs: 5))
        let result = await compactor.compact(&t)

        guard case .compacted(_, let usedModel, _) = result else {
            return XCTFail("expected .compacted")
        }
        XCTAssertFalse(usedModel, "throwing summarizer must fall back to deterministic")
        XCTAssertTrue(t.messages.first?.content.contains("Context compacted from") ?? false)
    }

    func testFallsBackToDeterministicSummaryWhenModelReturnsBlank() async {
        let compactor = ThreadCompactor(keepRecentMessages: 2, perMessageTokenFloor: 0,
                                        summarizer: BlankSummarizer())
        var t = thread(conversation(pairs: 5))
        let result = await compactor.compact(&t)
        guard case .compacted(_, let usedModel, _) = result else {
            return XCTFail("expected .compacted")
        }
        XCTAssertFalse(usedModel)
    }

    // MARK: - Idempotence / termination floor

    func testNoOlderTurnsWhenNothingToFold() async {
        let compactor = ThreadCompactor(keepRecentMessages: 6, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var t = thread(conversation(pairs: 2)) // 4 messages, all within the recent window
        let result = await compactor.compact(&t)
        XCTAssertEqual(result, .noOlderTurns)
        // Thread untouched: no summary spliced.
        XCTAssertFalse(t.messages.contains { $0.content == "SUM" })
    }

    func testSecondCompactionOnAlreadyCompactedThreadReportsNoOlderTurns() async {
        let compactor = ThreadCompactor(keepRecentMessages: 4, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var t = thread(conversation(pairs: 10))
        let first = await compactor.compact(&t) // now: summary + 4 recent = 5 messages
        guard case .compacted = first else { return XCTFail("first compaction should fold") }
        // A second compaction has only the single prior summary as "older" (1 < minOlderToFold), so it
        // must report noOlderTurns rather than re-summarizing its own summary forever.
        let second = await compactor.compact(&t)
        XCTAssertEqual(second, .noOlderTurns, "compaction must terminate, not fold its own summary forever")
        XCTAssertEqual(t.messages.filter { $0.content == "SUM" }.count, 1, "no second summary spliced")
    }

    func testCompactionTerminatesAcrossManyRoundsRegardlessOfThreadShape() async {
        // Stress the termination invariant: repeatedly compacting must reach noOlderTurns in a bounded
        // number of rounds for any starting thread, never loop.
        let compactor = ThreadCompactor(keepRecentMessages: 3, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var t = thread(conversation(pairs: 20))
        var rounds = 0
        while rounds < 100 {
            let result = await compactor.compact(&t)
            rounds += 1
            if result == .noOlderTurns { break }
        }
        XCTAssertLessThan(rounds, 100, "compaction must terminate quickly, not spin")
        let finalResult = await compactor.compact(&t)
        XCTAssertEqual(finalResult, .noOlderTurns)
    }

    // MARK: - Last-resort truncation

    func testLastResortTruncationOfOversizedKeptMessage() async {
        // A single giant tool result in the recent window: even with nothing older, the floor must
        // front-truncate it (keeping the tail) and mark it.
        let floorTokens = 100
        let compactor = ThreadCompactor(keepRecentMessages: 2, perMessageTokenFloor: floorTokens,
                                        summarizer: FixedSummarizer(text: "SUM"))
        let giant = String(repeating: "Z", count: 100_000) + "TAIL_MARKER"
        var messages = conversation(pairs: 5)
        messages.append(ChatMessage(role: .tool, content: giant))
        var t = thread(messages)
        let result = await compactor.compact(&t)

        guard case .compacted(_, _, let truncated) = result else {
            return XCTFail("expected .compacted")
        }
        XCTAssertTrue(truncated)
        let last = t.messages.last?.content ?? ""
        XCTAssertTrue(last.hasPrefix(ThreadCompactor.truncationMarker), "truncation must be marked")
        XCTAssertTrue(last.hasSuffix("TAIL_MARKER"), "truncation keeps the tail")
        XCTAssertLessThan(last.count, giant.count)
    }

    func testTruncationDisabledWhenFloorIsZero() async {
        let compactor = ThreadCompactor(keepRecentMessages: 2, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        let giant = String(repeating: "Z", count: 100_000)
        var t = thread([ChatMessage(role: .tool, content: giant)])
        let result = await compactor.compact(&t)
        // Only one message, within the recent window → nothing older; floor disabled → untouched.
        XCTAssertEqual(result, .noOlderTurns)
        XCTAssertEqual(t.messages.last?.content.count, giant.count)
    }

    // MARK: - Seam annotation

    func testSeamNoticeRecordedOnCompaction() async {
        let compactor = ThreadCompactor(keepRecentMessages: 4, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var t = thread(conversation(pairs: 10))
        _ = await compactor.compact(&t)

        let notice = t.events.last
        XCTAssertEqual(notice?.kind, .notice)
        XCTAssertTrue(notice?.summary.contains("Compacted") ?? false)
        // Payload is machine-readable for the transcript.
        let payloadJSON = notice?.payloadJSON ?? ""
        let payload = try? JSONHelpers.decode(CompactionSeamPayload.self, from: payloadJSON)
        XCTAssertEqual(payload?.summarizedTurns, 16)
        XCTAssertEqual(payload?.usedModelSummary, true)
    }

    func testNoSeamNoticeWhenNothingHappens() async {
        let compactor = ThreadCompactor(keepRecentMessages: 6, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var t = thread(conversation(pairs: 2))
        let eventsBefore = t.events.count
        _ = await compactor.compact(&t)
        XCTAssertEqual(t.events.count, eventsBefore, "a no-op compaction must not spam a seam event")
    }

    // MARK: - Robustness

    func testEmptyThreadCompactsToNoOlderTurns() async {
        let compactor = ThreadCompactor(summarizer: FixedSummarizer(text: "SUM"))
        var t = thread([])
        let result = await compactor.compact(&t)
        XCTAssertEqual(result, .noOlderTurns)
        XCTAssertTrue(t.messages.isEmpty)
    }

    func testKeepRecentClampedToAtLeastOne() async {
        let compactor = ThreadCompactor(keepRecentMessages: 0, perMessageTokenFloor: 0,
                                        summarizer: FixedSummarizer(text: "SUM"))
        var t = thread(conversation(pairs: 3))
        _ = await compactor.compact(&t)
        // At least the last message must be preserved.
        XCTAssertEqual(t.messages.last?.content, "assistant turn 2")
    }
}
