import Foundation
import XCTest
@testable import QuillCodeCore

final class FollowUpQueueTests: XCTestCase {
    private func item(_ text: String) -> FollowUpItem {
        FollowUpItem(id: UUID(), text: text, createdAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: enqueue

    func testEnqueueAppendsTrimmedToTailFIFO() {
        let start = [item("first")]
        let result = FollowUpQueue.enqueue("  second  ", into: start)
        XCTAssertEqual(result.queue.map(\.text), ["first", "second"])
        XCTAssertEqual(result.appended?.text, "second")
    }

    func testEnqueueStoresTrimmedText() {
        let result = FollowUpQueue.enqueue("\n  hello world \t", into: [])
        XCTAssertEqual(result.appended?.text, "hello world")
        XCTAssertEqual(result.queue.first?.text, "hello world")
    }

    func testEnqueueEmptyOrWhitespaceIsRejected() {
        let existing = [item("kept")]
        for blank in ["", "   ", "\n\t "] {
            let result = FollowUpQueue.enqueue(blank, into: existing)
            XCTAssertNil(result.appended, "\(blank.debugDescription) should not enqueue")
            XCTAssertEqual(result.queue.map(\.text), ["kept"], "queue must be unchanged")
        }
    }

    func testEnqueueUsesSuppliedIDAndTimestamp() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1234)
        let result = FollowUpQueue.enqueue("x", into: [], id: id, now: now)
        XCTAssertEqual(result.appended?.id, id)
        XCTAssertEqual(result.appended?.createdAt, now)
    }

    func testEnqueuePreservesExistingOrderAcrossMany() {
        var queue: [FollowUpItem] = []
        for text in ["a", "b", "c", "d"] {
            queue = FollowUpQueue.enqueue(text, into: queue).queue
        }
        XCTAssertEqual(queue.map(\.text), ["a", "b", "c", "d"])
    }

    // MARK: dequeue (drain)

    func testDequeueReturnsHeadAndRemainder() {
        let queue = [item("one"), item("two"), item("three")]
        let drain = FollowUpQueue.dequeue(queue)
        XCTAssertEqual(drain.next?.text, "one")
        XCTAssertEqual(drain.remaining.map(\.text), ["two", "three"])
    }

    func testDequeueEmptyReturnsNilAndKeepsQueue() {
        let drain = FollowUpQueue.dequeue([])
        XCTAssertNil(drain.next)
        XCTAssertEqual(drain.remaining.count, 0)
    }

    func testDequeueDrainsEachItemExactlyOnceInOrder() {
        var queue = [item("a"), item("b"), item("c")]
        var drained: [String] = []
        while true {
            let drain = FollowUpQueue.dequeue(queue)
            guard let next = drain.next else { break }
            drained.append(next.text)
            queue = drain.remaining
        }
        XCTAssertEqual(drained, ["a", "b", "c"])
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: delete

    func testDeleteRemovesMatchingID() {
        let keep = item("keep")
        let drop = item("drop")
        let queue = [keep, drop]
        let next = FollowUpQueue.delete(drop.id, from: queue)
        XCTAssertEqual(next.map(\.id), [keep.id])
    }

    func testDeleteUnknownIDIsNoOp() {
        let queue = [item("a"), item("b")]
        let next = FollowUpQueue.delete(UUID(), from: queue)
        XCTAssertEqual(next.map(\.text), ["a", "b"])
    }

    func testDeleteThenDequeueSkipsTheDeletedItem() {
        let a = item("a")
        let b = item("b")
        let queue = [a, b]
        // Delete the head before it drains: the next drain returns b, and a is never sent.
        let afterDelete = FollowUpQueue.delete(a.id, from: queue)
        let drain = FollowUpQueue.dequeue(afterDelete)
        XCTAssertEqual(drain.next?.text, "b")
        XCTAssertTrue(drain.remaining.isEmpty)
    }

    // MARK: model Codable round-trip

    func testFollowUpItemCodableRoundTrip() throws {
        let original = FollowUpItem(id: UUID(), text: "round trip", createdAt: Date(timeIntervalSince1970: 42))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FollowUpItem.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
