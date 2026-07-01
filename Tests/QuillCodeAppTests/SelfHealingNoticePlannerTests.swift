import XCTest
import QuillCodeAgent
@testable import QuillCodeApp

final class SelfHealingNoticePlannerTests: XCTestCase {
    func testFormatsEachCauseWithSelfHealingWording() {
        XCTAssertEqual(
            SelfHealingNoticePlanner.noticeSummary(attempt: 1, kind: .rateLimited),
            "Self-healing: retrying after a rate limit (attempt 1)"
        )
        XCTAssertEqual(
            SelfHealingNoticePlanner.noticeSummary(attempt: 2, kind: .serverOverloaded),
            "Self-healing: retrying after a server overload (attempt 2)"
        )
        XCTAssertEqual(
            SelfHealingNoticePlanner.noticeSummary(attempt: 3, kind: .transport),
            "Self-healing: retrying after a network error (attempt 3)"
        )
        XCTAssertEqual(
            SelfHealingNoticePlanner.noticeSummary(attempt: 1, kind: .none),
            "Self-healing: retrying after a transient error (attempt 1)"
        )
    }

    func testAlwaysLeadsWithSelfHealing() {
        // House style: "Self-healing", never "Fixing error".
        for kind in [TransientFailureClass.rateLimited, .serverOverloaded, .transport, .none] {
            XCTAssertTrue(SelfHealingNoticePlanner.noticeSummary(attempt: 1, kind: kind).hasPrefix("Self-healing:"))
        }
    }
}

final class RetryEventChannelTests: XCTestCase {
    func testRecordThenDrainReturnsAndClears() {
        let channel = RetryEventChannel()
        channel.record(attempt: 1, kind: .rateLimited)
        channel.record(attempt: 2, kind: .transport)
        let drained = channel.drain()
        XCTAssertEqual(drained, [RetryEvent(attempt: 1, kind: .rateLimited), RetryEvent(attempt: 2, kind: .transport)])
        XCTAssertTrue(channel.drain().isEmpty, "a second drain is empty")
    }

    func testConcurrentRecordsAreAllCaptured() {
        // The channel is written off the main actor by the retry decorator; the lock must not drop any.
        let channel = RetryEventChannel()
        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            channel.record(attempt: 1, kind: .transport)
        }
        XCTAssertEqual(channel.drain().count, 500)
    }
}
