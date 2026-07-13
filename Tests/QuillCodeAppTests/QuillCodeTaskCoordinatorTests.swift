import XCTest
@testable import QuillCodeApp

@MainActor
final class QuillCodeTaskCoordinatorTests: XCTestCase {
    func testStartIfIdleRunsOperationAndRejectsDuplicateSlot() async {
        let coordinator = QuillCodeTaskCoordinator<TestSlot>()
        let started = expectation(description: "operation started")
        let finished = expectation(description: "operation finished")
        var startCount = 0

        XCTAssertTrue(coordinator.startIfIdle(.send) {
            startCount += 1
            started.fulfill()
        } onFinish: {
            finished.fulfill()
        })
        XCTAssertFalse(coordinator.startIfIdle(.send) {
            XCTFail("duplicate operation should not start")
        })

        await fulfillment(of: [started, finished], timeout: 1)
        XCTAssertEqual(startCount, 1)
        XCTAssertFalse(coordinator.isRunning(.send))
    }

    func testCancelSlotStopsTaskWithoutRunningFinishCallback() async {
        let coordinator = QuillCodeTaskCoordinator<TestSlot>()
        let started = expectation(description: "operation started")
        let cancelled = expectation(description: "operation cancelled")
        let finished = expectation(description: "finish not called")
        finished.isInverted = true

        XCTAssertTrue(coordinator.startIfIdle(.send) {
            started.fulfill()
            await Self.waitForCancellation()
            cancelled.fulfill()
        } onFinish: {
            finished.fulfill()
        })

        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(coordinator.isRunning(.send))

        coordinator.cancel(.send)

        await fulfillment(of: [cancelled], timeout: 1)
        await fulfillment(of: [finished], timeout: 0.1)
        XCTAssertFalse(coordinator.isRunning(.send))
    }

    func testReplaceCancelsStaleTaskAndOnlyFinishesCurrentTask() async {
        let coordinator = QuillCodeTaskCoordinator<TestSlot>()
        let oldStarted = expectation(description: "old operation started")
        let oldCancelled = expectation(description: "old operation cancelled")
        let oldFinished = expectation(description: "old finish not called")
        oldFinished.isInverted = true
        let newStarted = expectation(description: "new operation started")
        let newFinished = expectation(description: "new operation finished")

        coordinator.replace(.send) {
            oldStarted.fulfill()
            await Self.waitForCancellation()
            oldCancelled.fulfill()
        } onFinish: {
            oldFinished.fulfill()
        }

        await fulfillment(of: [oldStarted], timeout: 1)
        XCTAssertTrue(coordinator.isRunning(.send))

        coordinator.replace(.send) {
            newStarted.fulfill()
        } onFinish: {
            newFinished.fulfill()
        }

        await fulfillment(of: [oldCancelled, newStarted, newFinished], timeout: 1)
        await fulfillment(of: [oldFinished], timeout: 0.1)
        XCTAssertFalse(coordinator.isRunning(.send))
    }

    func testEnqueueSerializesWorkBehindTheCurrentSlotOwner() async {
        let coordinator = QuillCodeTaskCoordinator<TestSlot>()
        let release = CoordinatorTestRelease()
        let firstStarted = expectation(description: "first operation started")
        let secondFinished = expectation(description: "queued operation finished")
        var order: [String] = []

        XCTAssertTrue(coordinator.startIfIdle(.send) {
            order.append("first-started")
            firstStarted.fulfill()
            await release.wait()
            order.append("first-finished")
        })
        coordinator.enqueue(.send) {
            order.append("second-started")
        } onFinish: {
            secondFinished.fulfill()
        }

        await fulfillment(of: [firstStarted], timeout: 1)
        XCTAssertEqual(order, ["first-started"])
        await release.open()
        await fulfillment(of: [secondFinished], timeout: 1)

        XCTAssertEqual(order, ["first-started", "first-finished", "second-started"])
        XCTAssertFalse(coordinator.isRunning(.send))
    }

    func testCancelAllStopsEverySlotWithoutFinishCallbacks() async {
        let coordinator = QuillCodeTaskCoordinator<TestSlot>()
        let sendStarted = expectation(description: "send started")
        let terminalStarted = expectation(description: "terminal started")
        let sendCancelled = expectation(description: "send cancelled")
        let terminalCancelled = expectation(description: "terminal cancelled")
        let finished = expectation(description: "finish not called")
        finished.expectedFulfillmentCount = 2
        finished.isInverted = true

        XCTAssertTrue(coordinator.startIfIdle(.send) {
            sendStarted.fulfill()
            await Self.waitForCancellation()
            sendCancelled.fulfill()
        } onFinish: {
            finished.fulfill()
        })
        XCTAssertTrue(coordinator.startIfIdle(.terminal) {
            terminalStarted.fulfill()
            await Self.waitForCancellation()
            terminalCancelled.fulfill()
        } onFinish: {
            finished.fulfill()
        })

        await fulfillment(of: [sendStarted, terminalStarted], timeout: 1)
        coordinator.cancelAll()

        await fulfillment(of: [sendCancelled, terminalCancelled], timeout: 1)
        await fulfillment(of: [finished], timeout: 0.1)
        XCTAssertFalse(coordinator.isRunning(.send))
        XCTAssertFalse(coordinator.isRunning(.terminal))
    }

    private static func waitForCancellation() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private actor CoordinatorTestRelease {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private enum TestSlot: Hashable, Sendable {
    case send
    case terminal
}
