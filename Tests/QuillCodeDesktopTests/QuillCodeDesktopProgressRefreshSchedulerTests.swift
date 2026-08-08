import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopProgressRefreshSchedulerTests: XCTestCase {
    func testBurstKeepsOnePendingRefreshAndFlushesOnce() {
        let scheduler = QuillCodeDesktopProgressRefreshScheduler(
            delayNanoseconds: 5_000_000_000
        )
        var refreshCount = 0

        for _ in 0..<10_000 {
            scheduler.schedule { refreshCount += 1 }
        }

        XCTAssertTrue(scheduler.hasPendingRefresh)
        XCTAssertEqual(refreshCount, 0)
        scheduler.flush { refreshCount += 1 }
        XCTAssertFalse(scheduler.hasPendingRefresh)
        XCTAssertEqual(refreshCount, 1)
    }

    func testLatestScheduledActionRunsAtCadenceBoundary() async throws {
        let scheduler = QuillCodeDesktopProgressRefreshScheduler(delayNanoseconds: 1_000_000)
        let refreshed = expectation(description: "scheduled refresh")
        var firstCount = 0
        var latestCount = 0

        scheduler.schedule { firstCount += 1 }
        scheduler.schedule {
            latestCount += 1
            refreshed.fulfill()
        }

        await fulfillment(of: [refreshed], timeout: 1)
        XCTAssertEqual(firstCount, 0)
        XCTAssertEqual(latestCount, 1)
        XCTAssertFalse(scheduler.hasPendingRefresh)
    }

    func testCancelPreventsDelayedRefresh() async throws {
        let scheduler = QuillCodeDesktopProgressRefreshScheduler(delayNanoseconds: 1_000_000)
        var refreshCount = 0

        scheduler.schedule { refreshCount += 1 }
        scheduler.cancel()
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(refreshCount, 0)
        XCTAssertFalse(scheduler.hasPendingRefresh)
    }

    func testPendingDelayDoesNotRetainScheduler() {
        weak var retainedScheduler: QuillCodeDesktopProgressRefreshScheduler?

        do {
            let scheduler = QuillCodeDesktopProgressRefreshScheduler(
                delayNanoseconds: 5_000_000_000
            )
            retainedScheduler = scheduler
            scheduler.schedule {}
        }

        XCTAssertNil(retainedScheduler)
    }
}
