import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class TranscriptScrollFollowTests: XCTestCase {
    func testContentSignatureChangesWhenThinkingTraceGrowsWithStableID() {
        // The whole point: the signature must change as streamed content grows EVEN THOUGH the tail
        // id is stable — which `scrollAnchorID` (id-only) cannot do. Use thinking so we control the id.
        let base = TranscriptThinkingSurface(id: "think-1", title: "Thinking", subtitle: "…", traceLines: ["a"])
        let grown = TranscriptThinkingSurface(id: "think-1", title: "Thinking", subtitle: "…", traceLines: ["a", "bcd"])
        let before = TranscriptSurface(messages: [], toolCards: [], thinking: base)
        let after = TranscriptSurface(messages: [], toolCards: [], thinking: grown)

        XCTAssertNotEqual(
            TranscriptScrollFollow.contentSignature(for: before),
            TranscriptScrollFollow.contentSignature(for: after)
        )
    }

    func testContentSignatureIsStableForIdenticalTranscripts() {
        let message = MessageSurface(message: ChatMessage(role: .assistant, content: "Hello, world"))
        let a = TranscriptSurface(messages: [message], toolCards: [])
        let b = TranscriptSurface(messages: [message], toolCards: [])

        XCTAssertEqual(
            TranscriptScrollFollow.contentSignature(for: a),
            TranscriptScrollFollow.contentSignature(for: b)
        )
    }

    func testContentSignatureTracksTrailingMessageLength() {
        let shortMessage = MessageSurface(message: ChatMessage(role: .assistant, content: "Hi"))
        let longMessage = MessageSurface(message: ChatMessage(role: .assistant, content: "Hi there, friend"))

        XCTAssertNotEqual(
            TranscriptScrollFollow.contentSignature(for: TranscriptSurface(messages: [shortMessage], toolCards: [])),
            TranscriptScrollFollow.contentSignature(for: TranscriptSurface(messages: [longMessage], toolCards: []))
        )
    }

    func testIsPinnedToBottomHonorsThreshold() {
        // Sentinel within (or at) the threshold of the viewport bottom => pinned; farther => not.
        XCTAssertTrue(TranscriptScrollFollow.isPinnedToBottom(bottomSentinelMaxY: 500, viewportHeight: 480, threshold: 60))
        XCTAssertTrue(TranscriptScrollFollow.isPinnedToBottom(bottomSentinelMaxY: 540, viewportHeight: 480, threshold: 60))
        XCTAssertFalse(TranscriptScrollFollow.isPinnedToBottom(bottomSentinelMaxY: 800, viewportHeight: 480, threshold: 60))
    }
}
