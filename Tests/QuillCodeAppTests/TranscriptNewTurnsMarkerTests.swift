import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class TranscriptNewTurnsMarkerTests: XCTestCase {
    private func timeline(_ count: Int) -> [TranscriptTimelineItemSurface] {
        (0..<count).map { index in
            TranscriptTimelineItemSurface.message(
                MessageSurface(message: ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", index))")!,
                    role: index.isMultiple(of: 2) ? .user : .assistant,
                    content: "turn \(index)"
                ))
            )
        }
    }

    func testNilMarkerShowsNoPill() {
        let marker = TranscriptNewTurnsMarker()
        XCTAssertNil(TranscriptNewTurnsResolver.resolve(timeline: timeline(3), marker: marker))
    }

    func testMarkerAtLastItemShowsNoPill() {
        let items = timeline(3)
        var marker = TranscriptNewTurnsMarker()
        marker.markSeen(timeline: items)
        XCTAssertEqual(marker.lastSeenItemID, items.last?.id)
        XCTAssertNil(TranscriptNewTurnsResolver.resolve(timeline: items, marker: marker))
    }

    func testNewTurnsCountedAfterMarker() {
        let seen = timeline(3)
        var marker = TranscriptNewTurnsMarker()
        marker.markSeen(timeline: seen)

        // Two more turns arrive.
        let grown = timeline(5)
        let pill = TranscriptNewTurnsResolver.resolve(timeline: grown, marker: marker)
        XCTAssertEqual(pill?.count, 2)
        XCTAssertEqual(pill?.firstUnseenItemID, grown[3].id)
        XCTAssertEqual(pill?.label, "2 new turns")
    }

    func testSingleNewTurnIsSingularLabel() {
        let seen = timeline(3)
        var marker = TranscriptNewTurnsMarker()
        marker.markSeen(timeline: seen)
        let grown = timeline(4)
        let pill = TranscriptNewTurnsResolver.resolve(timeline: grown, marker: marker)
        XCTAssertEqual(pill?.count, 1)
        XCTAssertEqual(pill?.label, "1 new turn")
    }

    func testStaleMarkerNotInTimelineShowsNoPillAndNeverNegative() {
        // Marker points at an item that was compacted/forked away.
        let marker = TranscriptNewTurnsMarker(lastSeenItemID: "message-does-not-exist")
        XCTAssertNil(TranscriptNewTurnsResolver.resolve(timeline: timeline(4), marker: marker))
    }

    func testMarkerSurvivesReloadRoundTrip() throws {
        let items = timeline(4)
        var marker = TranscriptNewTurnsMarker()
        marker.markSeen(timeline: items)

        let encoded = try JSONEncoder().encode(marker)
        let decoded = try JSONDecoder().decode(TranscriptNewTurnsMarker.self, from: encoded)
        XCTAssertEqual(decoded, marker)

        // After a "reload" the pill derivation is identical.
        let grown = timeline(6)
        XCTAssertEqual(
            TranscriptNewTurnsResolver.resolve(timeline: grown, marker: decoded)?.count,
            2
        )
    }

    func testMarkSeenOnEmptyTimelineLeavesMarkerUnchanged() {
        var marker = TranscriptNewTurnsMarker(lastSeenItemID: "keep-me")
        marker.markSeen(timeline: [])
        XCTAssertEqual(marker.lastSeenItemID, "keep-me")
    }

    func testMarkingSeenAgainAfterGrowthClearsPill() {
        let seen = timeline(3)
        var marker = TranscriptNewTurnsMarker()
        marker.markSeen(timeline: seen)

        let grown = timeline(5)
        XCTAssertNotNil(TranscriptNewTurnsResolver.resolve(timeline: grown, marker: marker))

        // Once the user catches up, marking seen again removes the pill.
        marker.markSeen(timeline: grown)
        XCTAssertNil(TranscriptNewTurnsResolver.resolve(timeline: grown, marker: marker))
    }

    // MARK: - Per-thread tracker (the semantics the native pill drives)

    private let threadA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let threadB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    func testTrackerShowsNoPillOnFirstViewOfAThread() {
        var tracker = TranscriptNewTurnsTracker()
        // Observing (foreground) a thread never seen before must NOT create a pill: there is no
        // acknowledged watermark yet.
        tracker.observe(threadID: threadA, timeline: timeline(3))
        XCTAssertNil(tracker.pill(for: threadA, timeline: timeline(3)))
    }

    func testTrackerObserveDoesNotAdvanceWatermarkSoBackgroundGrowthSurfaces() {
        var tracker = TranscriptNewTurnsTracker()
        // View A (3 turns), then leave A — its watermark is set to A's end.
        tracker.observe(threadID: threadA, timeline: timeline(3))
        tracker.leave(threadID: threadA)
        // A grows to 5 in the background. We only "observe" it again on return — which must not
        // advance the watermark. The pill must appear.
        tracker.observe(threadID: threadA, timeline: timeline(5))
        let pill = tracker.pill(for: threadA, timeline: timeline(5))
        XCTAssertEqual(pill?.count, 2)
        XCTAssertEqual(pill?.firstUnseenItemID, timeline(5)[3].id)
    }

    func testTrackerLeaveUsesTailObservedWhileForegroundNotLaterGrowth() {
        var tracker = TranscriptNewTurnsTracker()
        // Foreground A at 3 turns.
        tracker.observe(threadID: threadA, timeline: timeline(3))
        // Leave — watermark should be A's 3rd item, the last thing we had on screen.
        tracker.leave(threadID: threadA)
        // On return with 4 turns, exactly 1 is new.
        tracker.observe(threadID: threadA, timeline: timeline(4))
        XCTAssertEqual(tracker.pill(for: threadA, timeline: timeline(4))?.count, 1)
    }

    func testTrackerSwitchingThreadsDoesNotClobberEachOthersWatermarks() {
        var tracker = TranscriptNewTurnsTracker()
        // See A (2), leave A. See B (3), leave B.
        tracker.observe(threadID: threadA, timeline: timeline(2))
        tracker.leave(threadID: threadA)
        tracker.observe(threadID: threadB, timeline: timeline(3))
        tracker.leave(threadID: threadB)
        // Both grow in the background; each thread's own delta is independent.
        XCTAssertEqual(tracker.pill(for: threadA, timeline: timeline(5))?.count, 3)
        XCTAssertEqual(tracker.pill(for: threadB, timeline: timeline(6))?.count, 3)
    }

    func testTrackerMarkSeenClearsPill() {
        var tracker = TranscriptNewTurnsTracker()
        tracker.observe(threadID: threadA, timeline: timeline(3))
        tracker.leave(threadID: threadA)
        tracker.observe(threadID: threadA, timeline: timeline(5))
        XCTAssertNotNil(tracker.pill(for: threadA, timeline: timeline(5)))
        // Tapping the pill (markSeen) catches up to the current end.
        tracker.markSeen(threadID: threadA, timeline: timeline(5))
        XCTAssertNil(tracker.pill(for: threadA, timeline: timeline(5)))
    }

    func testTrackerNewChatThenBackgroundGrowThenReturnShowsPill() {
        // MAJOR 2 regression: the New Chat path. The watermark must advance when LEAVING A via New
        // Chat (a switch to a brand-new EMPTY thread), so background growth on A surfaces on
        // return. This is the exact transition sequence the fixed native wiring delivers from the
        // stable parent (which fires even though the new thread's transcript is empty).
        let newChatThread = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
        var tracker = TranscriptNewTurnsTracker()

        // View A (3 turns).
        tracker.observe(threadID: threadA, timeline: timeline(3))
        // New Chat: leave A (advances A's watermark to its tail), then observe the new EMPTY thread.
        tracker.leave(threadID: threadA)
        tracker.observe(threadID: newChatThread, timeline: [])
        // A grows to 5 in the background while the empty new chat is foreground.
        // Return to A.
        tracker.leave(threadID: newChatThread)
        tracker.observe(threadID: threadA, timeline: timeline(5))

        let pill = tracker.pill(for: threadA, timeline: timeline(5))
        XCTAssertEqual(pill?.count, 2, "New-Chat → background-grow → return must show the pill")
        XCTAssertEqual(pill?.firstUnseenItemID, timeline(5)[3].id)
    }

    func testTrackerReturnWithoutLeavingNeverShowsPillForNeverLeftThread() {
        // Fail-on-revert guard for MAJOR 2: if the view re-observes a thread on return and that
        // observe wrongly advanced the watermark, this would still pass — so we assert the
        // *positive*: a thread that was left THEN grew MUST show a pill on return. (The buggy impl
        // advanced the watermark on every appear/scroll, making this nil.)
        var tracker = TranscriptNewTurnsTracker()
        tracker.observe(threadID: threadA, timeline: timeline(3))
        tracker.leave(threadID: threadA)
        // Simulate the native return sequence: onChange(threadID) observe, then onAppear observe,
        // then scrollAnchorID-change observe — none may advance the watermark.
        tracker.observe(threadID: threadA, timeline: timeline(5))
        tracker.observe(threadID: threadA, timeline: timeline(5))
        tracker.observe(threadID: threadA, timeline: timeline(5))
        XCTAssertEqual(
            tracker.pill(for: threadA, timeline: timeline(5))?.count,
            2,
            "repeated observe() on return must not advance the watermark; the pill must survive"
        )
    }

    func testTrackerNilThreadIsInert() {
        var tracker = TranscriptNewTurnsTracker()
        tracker.observe(threadID: nil, timeline: timeline(3))
        tracker.leave(threadID: nil)
        tracker.markSeen(threadID: nil, timeline: timeline(3))
        XCTAssertNil(tracker.pill(for: nil, timeline: timeline(3)))
    }
}
