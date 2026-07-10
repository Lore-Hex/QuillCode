import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class ContextTokenEstimatorTests: XCTestCase {
    func testEmptyThreadIsZero() {
        XCTAssertEqual(ContextTokenEstimator.estimatedTokens(for: ChatThread()), 0)
    }

    func testEmptyMessageListIsZero() {
        XCTAssertEqual(ContextTokenEstimator.estimatedTokens(for: [ChatMessage]()), 0)
    }

    func testGrowsMonotonicallyWithContent() {
        let short = [ChatMessage(role: .user, content: "hi")]
        let long = [ChatMessage(role: .user, content: String(repeating: "word ", count: 1_000))]
        XCTAssertLessThan(
            ContextTokenEstimator.estimatedTokens(for: short),
            ContextTokenEstimator.estimatedTokens(for: long)
        )
    }

    func testPerMessageOverheadCounted() {
        // Many empty messages still cost overhead, so an empty-content thread of N messages is > 0.
        let messages = (0..<10).map { _ in ChatMessage(role: .user, content: "") }
        XCTAssertEqual(
            ContextTokenEstimator.estimatedTokens(for: messages),
            10 * ContextTokenEstimator.perMessageOverheadTokens
        )
    }

    func testImageAttachmentsAddConservativeContextAllowance() throws {
        let attachment = try XCTUnwrap(ChatAttachment(
            displayName: "screen.png",
            format: .png,
            localURL: URL(fileURLWithPath: "/tmp/screen.png"),
            byteCount: 8
        ))
        let message = ChatMessage(role: .user, content: "", attachments: [attachment])

        XCTAssertEqual(
            ContextTokenEstimator.estimatedTokens(for: [message]),
            ContextTokenEstimator.perMessageOverheadTokens
                + ContextTokenEstimator.perImageAttachmentTokens
        )
    }

    func testSingleTextEstimateRoundsUp() {
        // 5 chars / 4 per token, rounded up = 2 tokens.
        XCTAssertEqual(ContextTokenEstimator.estimatedTokens(forText: "hello"), 2)
        XCTAssertEqual(ContextTokenEstimator.estimatedTokens(forText: ""), 0)
    }

    func testHugeContentDoesNotTrapAndIsBounded() {
        // A single multi-megabyte message: must return a large finite value, never crash.
        let huge = ChatMessage(role: .tool, content: String(repeating: "a", count: 5_000_000))
        let estimate = ContextTokenEstimator.estimatedTokens(for: [huge])
        XCTAssertGreaterThan(estimate, 1_000_000)
        XCTAssertLessThanOrEqual(estimate, ContextTokenEstimator.maxEstimatedTokens)
    }

    func testEstimateClampsAtCeiling() {
        // Enough giant messages to blow past the ceiling; the estimator must clamp, not overflow.
        let giant = ChatMessage(role: .tool, content: String(repeating: "a", count: 5_000_000))
        let messages = Array(repeating: giant, count: 2_000)
        XCTAssertEqual(
            ContextTokenEstimator.estimatedTokens(for: messages),
            ContextTokenEstimator.maxEstimatedTokens
        )
    }
}
