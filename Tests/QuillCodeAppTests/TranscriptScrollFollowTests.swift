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

    // MARK: - resolvePinned (the pin transition)

    func testResolvePinnedWithinThresholdRepinsRegardlessOfScroll() {
        // Within threshold dominates: whatever moved the end back into reach, we (re)pin.
        XCTAssertTrue(resolve(current: false, maxY: 500, isUserScrollUp: true))
        XCTAssertTrue(resolve(current: false, maxY: 500, isUserScrollUp: false))
    }

    func testResolvePinnedBeyondThresholdGrowthPreservesUserScrollUnpins() {
        // Beyond threshold: content growth (isUserScrollUp=false) PRESERVES the prior state so an
        // at-bottom reader keeps being followed through a big chunk; only a real scroll-up un-pins.
        XCTAssertTrue(resolve(current: true, maxY: 800, isUserScrollUp: false))    // growth keeps pin
        XCTAssertFalse(resolve(current: true, maxY: 800, isUserScrollUp: true))    // scroll-up un-pins
        XCTAssertFalse(resolve(current: false, maxY: 800, isUserScrollUp: false))  // scrolled-up stays
        XCTAssertFalse(resolve(current: false, maxY: 800, isUserScrollUp: true))
    }

    func testResizeNeverStrandsAtBottomReaderAndNeverRepinsScrolledUp() {
        // The viewport-height (resize) path passes isUserScrollUp:false — it may re-pin within the
        // threshold but never un-pins an at-bottom reader and never yanks a scrolled-up one down.
        XCTAssertTrue(resolve(current: true, maxY: 800, isUserScrollUp: false))
        XCTAssertFalse(resolve(current: false, maxY: 800, isUserScrollUp: false))
    }

    // MARK: - pinnedAfterScrollSample (orthogonal content-offset direction)

    func testLargeChunkAtBottomKeepsPinned() {
        // THE regression: a big chunk widens the sentinel gap (maxY 800) but the content TOP does not
        // move (offset unchanged) ⇒ not a scroll ⇒ an at-bottom reader stays pinned and keeps following.
        // The pre-fix / signature-only fixes both dropped the follow here under streaming.
        XCTAssertTrue(scrollSample(current: true, maxY: 800, topMinY: -100, previous: -100))
    }

    func testFollowScrollAnimationFrameKeepsPinned() {
        // Mid follow-scroll the content top moves further NEGATIVE (toward the bottom); that must never
        // read as a scroll-up. This is the exact intermediate frame that re-broke the signature-only fix.
        XCTAssertTrue(scrollSample(current: true, maxY: 800, topMinY: -300, previous: -100))
    }

    func testUserScrollUpUnpinsEvenWhileContentIsLarge() {
        // The reader drags the content DOWN (top offset increases past epsilon) while the gap is large:
        // un-pin. Works even mid-stream — the offset signal is independent of content growth.
        XCTAssertFalse(scrollSample(current: true, maxY: 800, topMinY: -40, previous: -100))
    }

    func testStreamingDoesNotRepinAScrolledUpReader() {
        // Already scrolled up (current false); a chunk grows (top unchanged) ⇒ stays un-pinned so the
        // Jump-to-latest chip keeps floating instead of yanking them down.
        XCTAssertFalse(scrollSample(current: false, maxY: 800, topMinY: -100, previous: -100))
    }

    func testReturnWithinThresholdRepinsRegardlessOfDirection() {
        // Even a scroll-up delta re-pins once the end is back within threshold (within-threshold wins).
        XCTAssertTrue(scrollSample(current: false, maxY: 500, topMinY: -20, previous: -80))
    }

    func testBoundaryInclusiveAtThreshold() {
        XCTAssertTrue(scrollSample(current: false, maxY: 540, topMinY: -50, previous: -50))   // gap 60
    }

    func testJustPastBoundaryStaysUnpinnedWithoutScroll() {
        XCTAssertFalse(scrollSample(current: false, maxY: 541, topMinY: -50, previous: -50))  // gap 61
    }

    func testJustPastBoundaryGrowthPreservesPin() {
        XCTAssertTrue(scrollSample(current: true, maxY: 541, topMinY: -50, previous: -50))
    }

    func testSubEpsilonOffsetJitterDoesNotUnpin() {
        // 0.3pt of layout jitter must not be read as a scroll-up (epsilon 0.5).
        XCTAssertTrue(scrollSample(current: true, maxY: 800, topMinY: -99.7, previous: -100))
    }

    private func resolve(current: Bool, maxY: CGFloat, isUserScrollUp: Bool) -> Bool {
        TranscriptScrollFollow.resolvePinned(
            current: current,
            bottomSentinelMaxY: maxY,
            viewportHeight: 480,
            threshold: 60,
            isUserScrollUp: isUserScrollUp
        )
    }

    private func scrollSample(current: Bool, maxY: CGFloat, topMinY: CGFloat, previous: CGFloat) -> Bool {
        TranscriptScrollFollow.pinnedAfterScrollSample(
            current: current,
            bottomSentinelMaxY: maxY,
            viewportHeight: 480,
            threshold: 60,
            contentTopMinY: topMinY,
            previousContentTopMinY: previous
        )
    }
}
