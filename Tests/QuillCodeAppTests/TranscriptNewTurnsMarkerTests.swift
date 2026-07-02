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
}
