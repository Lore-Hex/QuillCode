import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopLatestTaskSchedulerTests: XCTestCase {
    func testBurstRunsOnlyActiveAndLatestPendingWork() async throws {
        var continuations: [Int: CheckedContinuation<Int, any Error>] = [:]
        var started: [Int] = []
        var delivered: [Int] = []
        let scheduler = QuillCodeDesktopLatestTaskScheduler<String, Int, Int>(
            operation: { input in
                started.append(input)
                return try await withCheckedThrowingContinuation { continuation in
                    continuations[input] = continuation
                }
            },
            delivery: { _, output in delivered.append(output) }
        )

        scheduler.schedule(1, for: "tab")
        await waitUntil { continuations[1] != nil }
        for input in 2...10_000 {
            scheduler.schedule(input, for: "tab")
        }

        XCTAssertEqual(scheduler.activeWorkerCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 1)
        continuations[1]?.resume(returning: 1)
        await waitUntil { continuations[10_000] != nil }

        XCTAssertEqual(started, [1, 10_000])
        XCTAssertTrue(delivered.isEmpty, "the superseded active result must not publish")
        continuations[10_000]?.resume(returning: 10_000)
        await waitUntil { scheduler.activeWorkerCount == 0 }

        XCTAssertEqual(delivered, [10_000])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testKeysRunIndependently() async {
        var continuations: [String: CheckedContinuation<String, any Error>] = [:]
        var delivered: [String] = []
        let scheduler = QuillCodeDesktopLatestTaskScheduler<String, String, String>(
            operation: { input in
                try await withCheckedThrowingContinuation { continuation in
                    continuations[input] = continuation
                }
            },
            delivery: { _, output in delivered.append(output) }
        )

        scheduler.schedule("first", for: "tab-1")
        scheduler.schedule("second", for: "tab-2")
        await waitUntil { continuations.count == 2 }

        XCTAssertEqual(scheduler.activeWorkerCount, 2)
        continuations["first"]?.resume(returning: "first")
        continuations["second"]?.resume(returning: "second")
        await waitUntil { scheduler.activeWorkerCount == 0 }

        XCTAssertEqual(Set(delivered), ["first", "second"])
    }

    func testCancellationDropsPendingAndActiveResults() async {
        var continuation: CheckedContinuation<Int, any Error>?
        var deliveryCount = 0
        let scheduler = QuillCodeDesktopLatestTaskScheduler<String, Int, Int>(
            operation: { input in
                try await withCheckedThrowingContinuation { captured in
                    continuation = captured
                }
            },
            delivery: { _, _ in deliveryCount += 1 }
        )

        scheduler.schedule(1, for: "tab")
        await waitUntil { continuation != nil }
        scheduler.schedule(2, for: "tab")
        scheduler.cancel(for: "tab")

        XCTAssertEqual(scheduler.activeWorkerCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        continuation?.resume(returning: 1)
        await Task.yield()
        XCTAssertEqual(deliveryCount, 0)
    }

    func testFailedActiveWorkStillRunsLatestPendingRequest() async {
        var firstContinuation: CheckedContinuation<Void, Never>?
        var started: [Int] = []
        var delivered: [Int] = []
        let scheduler = QuillCodeDesktopLatestTaskScheduler<String, Int, Int>(
            operation: { input in
                started.append(input)
                if input == 1 {
                    await withCheckedContinuation { continuation in
                        firstContinuation = continuation
                    }
                    throw TestFailure.expected
                }
                return input
            },
            delivery: { _, output in delivered.append(output) }
        )

        scheduler.schedule(1, for: "tab")
        await waitUntil { firstContinuation != nil }
        scheduler.schedule(2, for: "tab")
        firstContinuation?.resume()
        await waitUntil { scheduler.activeWorkerCount == 0 }

        XCTAssertEqual(started, [1, 2])
        XCTAssertEqual(delivered, [2])
    }

    func testCancelledWorkerCannotRemoveReplacementForSameKey() async {
        var continuations: [Int: CheckedContinuation<Int, any Error>] = [:]
        var delivered: [Int] = []
        let scheduler = QuillCodeDesktopLatestTaskScheduler<String, Int, Int>(
            operation: { input in
                try await withCheckedThrowingContinuation { continuation in
                    continuations[input] = continuation
                }
            },
            delivery: { _, output in delivered.append(output) }
        )

        scheduler.schedule(1, for: "tab")
        await waitUntil { continuations[1] != nil }
        scheduler.cancel(for: "tab")
        scheduler.schedule(2, for: "tab")
        await waitUntil { continuations[2] != nil }

        continuations[1]?.resume(returning: 1)
        await Task.yield()
        XCTAssertEqual(scheduler.activeWorkerCount, 1)
        XCTAssertTrue(delivered.isEmpty)

        continuations[2]?.resume(returning: 2)
        await waitUntil { scheduler.activeWorkerCount == 0 }
        XCTAssertEqual(delivered, [2])
    }

    func testCancelAllReleasesEveryKeyAndPendingRequest() async {
        var continuations: [String: CheckedContinuation<String, any Error>] = [:]
        var deliveryCount = 0
        let scheduler = QuillCodeDesktopLatestTaskScheduler<String, String, String>(
            operation: { input in
                try await withCheckedThrowingContinuation { continuation in
                    continuations[input] = continuation
                }
            },
            delivery: { _, _ in deliveryCount += 1 }
        )

        scheduler.schedule("first-active", for: "tab-1")
        scheduler.schedule("second-active", for: "tab-2")
        await waitUntil { continuations.count == 2 }
        scheduler.schedule("first-pending", for: "tab-1")
        scheduler.schedule("second-pending", for: "tab-2")
        scheduler.cancelAll()

        XCTAssertEqual(scheduler.activeWorkerCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        continuations.values.forEach { $0.resume(returning: "ignored") }
        await Task.yield()
        XCTAssertEqual(deliveryCount, 0)
    }

    func testActiveWorkerDoesNotRetainScheduler() async {
        weak var retainedScheduler: QuillCodeDesktopLatestTaskScheduler<String, Int, Int>?

        do {
            let scheduler = QuillCodeDesktopLatestTaskScheduler<String, Int, Int>(
                operation: { _ in
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return 1
                },
                delivery: { _, _ in }
            )
            retainedScheduler = scheduler
            scheduler.schedule(1, for: "tab")
            await waitUntil { scheduler.activeWorkerCount == 1 }
        }

        XCTAssertNil(retainedScheduler)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "condition did not become true", file: file, line: line)
    }

    private enum TestFailure: Error {
        case expected
    }
}
