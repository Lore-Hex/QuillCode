import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class TranscriptSearchIndexTests: XCTestCase {
    private func transcript(
        messages: [(ChatRole, String)] = [],
        toolCards: [ToolCardState] = []
    ) -> TranscriptSurface {
        TranscriptSurface(
            messages: messages.map { MessageSurface(message: ChatMessage(role: $0.0, content: $0.1)) },
            toolCards: toolCards
        )
    }

    func testEmptyAndBlankQueryMatchesNothing() {
        let surface = transcript(messages: [(.user, "hello world")])
        XCTAssertTrue(TranscriptSearchIndex.build(transcript: surface, query: "").isEmpty)
        XCTAssertTrue(TranscriptSearchIndex.build(transcript: surface, query: "   ").isEmpty)
        XCTAssertTrue(TranscriptSearchIndex.build(transcript: surface, query: "\n\t").isEmpty)
    }

    func testCaseInsensitiveMatchAcrossMessagesAndToolCards() {
        let card = ToolCardState(
            id: "tool-1",
            title: "Run Shell",
            subtitle: "swift test",
            status: .done,
            inputJSON: #"{"command":"swift test"}"#,
            outputJSON: #"{"stdout":"OK"}"#,
            artifacts: [.init(value: "/tmp/report.txt")]
        )
        let surface = transcript(
            messages: [(.user, "Run tests"), (.assistant, "All checks passed")],
            toolCards: [card]
        )

        XCTAssertEqual(TranscriptSearchIndex.build(transcript: surface, query: "checks").matches.map(\.label), ["Assistant"])
        XCTAssertEqual(TranscriptSearchIndex.build(transcript: surface, query: "SWIFT").matches.map(\.label), ["Run Shell"])
        XCTAssertEqual(TranscriptSearchIndex.build(transcript: surface, query: "report").matches.map(\.label), ["Run Shell"])
    }

    func testToolSearchLabelsUseFriendlyNamesWhileRawIdentifiersRemainSearchable() {
        let card = ToolCardState(
            id: "tool-1",
            title: "host.shell.run",
            subtitle: "swift test",
            status: .done
        )
        let surface = transcript(toolCards: [card])

        XCTAssertEqual(
            TranscriptSearchIndex.build(transcript: surface, query: "Shell command").matches.map(\.label),
            ["Shell command"]
        )
        XCTAssertEqual(
            TranscriptSearchIndex.build(transcript: surface, query: "host.shell.run").matches.map(\.label),
            ["Shell command"]
        )
    }

    func testMatchRangesAreCharacterOffsetsAndNonOverlapping() {
        // "aaaa" contains "aa" twice (non-overlapping), at offsets 0 and 2.
        let ranges = TranscriptSearchIndex.literalRanges(of: Array("aa"), in: "aaaa")
        XCTAssertEqual(ranges, [
            TranscriptSearchIndex.MatchRange(start: 0, length: 2),
            TranscriptSearchIndex.MatchRange(start: 2, length: 2)
        ])
    }

    func testMultipleOccurrencesWithinOneItemAreAllReported() {
        let surface = transcript(messages: [(.user, "test the test then test again")])
        let index = TranscriptSearchIndex.build(transcript: surface, query: "test")
        XCTAssertEqual(index.matches.count, 1)
        // "test" appears three times in the body (role "user" also does not contain it).
        XCTAssertEqual(index.matches.first?.ranges.count, 3)
        XCTAssertEqual(index.totalOccurrences, 3)
    }

    func testSpecialRegexCharactersAreTreatedLiterally() {
        let surface = transcript(messages: [(.user, "price is $5.00 (approx) [rounded] a.b")])
        // A regex would treat these as metacharacters; literal search must find the exact text.
        XCTAssertEqual(TranscriptSearchIndex.build(transcript: surface, query: "$5.00").count, 1)
        XCTAssertEqual(TranscriptSearchIndex.build(transcript: surface, query: "(approx)").count, 1)
        XCTAssertEqual(TranscriptSearchIndex.build(transcript: surface, query: "[rounded]").count, 1)
        // "a.b" as regex would also match "axb"; here only the literal "a.b" is present, and a
        // literal search for "a.b" must NOT match a body that only has "axb".
        let axb = transcript(messages: [(.user, "axb")])
        XCTAssertTrue(TranscriptSearchIndex.build(transcript: axb, query: "a.b").isEmpty)
    }

    func testUnicodeGraphemeMatching() {
        let surface = transcript(messages: [(.user, "deploy 🚀 to prod 🚀 now")])
        let index = TranscriptSearchIndex.build(transcript: surface, query: "🚀")
        XCTAssertEqual(index.matches.first?.ranges.count, 2)
        // Accented text matches case-insensitively as its own grapheme.
        let accented = transcript(messages: [(.assistant, "Café Café")])
        XCTAssertEqual(TranscriptSearchIndex.build(transcript: accented, query: "café").matches.first?.ranges.count, 2)
    }

    func testHugeTranscriptStaysLinearAndCorrect() {
        // 5,000 messages, one match near the end — a quadratic implementation would choke; this
        // asserts correctness and, implicitly by finishing quickly, bounded cost.
        var msgs: [(ChatRole, String)] = (0..<5_000).map { (.user, "filler line number \($0)") }
        msgs.append((.assistant, "unique-needle-here"))
        let surface = transcript(messages: msgs)
        let index = TranscriptSearchIndex.build(transcript: surface, query: "unique-needle-here")
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.matches.first?.label, "Assistant")
    }

    // MARK: - Cursor

    func testCursorWrapsForwardAndBackward() {
        var cursor = TranscriptSearchCursor(count: 3)
        XCTAssertEqual(cursor.activeIndex, 0)
        XCTAssertEqual(cursor.humanPosition, 1)
        cursor.next(); XCTAssertEqual(cursor.activeIndex, 1)
        cursor.next(); XCTAssertEqual(cursor.activeIndex, 2)
        cursor.next(); XCTAssertEqual(cursor.activeIndex, 0) // wraps
        cursor.previous(); XCTAssertEqual(cursor.activeIndex, 2) // wraps backward, no negative modulo
    }

    func testCursorClampsInitialIndexAndHandlesEmpty() {
        let clamped = TranscriptSearchCursor(activeIndex: 99, count: 3)
        XCTAssertEqual(clamped.activeIndex, 2)

        var empty = TranscriptSearchCursor(activeIndex: 5, count: 0)
        XCTAssertEqual(empty.activeIndex, 0)
        XCTAssertEqual(empty.humanPosition, 0)
        empty.next(); XCTAssertEqual(empty.activeIndex, 0) // no crash, no movement
        empty.previous(); XCTAssertEqual(empty.activeIndex, 0)
    }

    func testCursorResetGoesToFirst() {
        var cursor = TranscriptSearchCursor(activeIndex: 2, count: 3)
        cursor.reset()
        XCTAssertEqual(cursor.activeIndex, 0)
    }
}
