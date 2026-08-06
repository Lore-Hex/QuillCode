import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopProgressRefreshSchedulerTests: XCTestCase {
    func testBurstRequestsCoalesceIntoOneRefreshPerInterval() async throws {
        let scheduler = QuillCodeDesktopProgressRefreshScheduler(delayNanoseconds: 10_000_000)
        var refreshCount = 0

        for _ in 0..<100 {
            scheduler.request { refreshCount += 1 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(refreshCount, 1)

        for _ in 0..<25 {
            scheduler.request { refreshCount += 1 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(refreshCount, 2)
    }

    func testCancelPendingPreventsLateRefresh() async throws {
        let scheduler = QuillCodeDesktopProgressRefreshScheduler(delayNanoseconds: 20_000_000)
        var refreshCount = 0

        scheduler.request { refreshCount += 1 }
        scheduler.cancelPending()
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(refreshCount, 0)
    }
}
