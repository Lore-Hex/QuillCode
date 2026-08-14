import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceAutomationEventPollerTests: XCTestCase {
    func testAsyncPollingLeavesMainThreadAndPreservesAutomationOrder() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let tracker = AutomationPollTracker(delay: 0.04)
        let automations = (0..<8).map { index in
            eventAutomation(index: index, now: now)
        }
        let sources = Dictionary(uniqueKeysWithValues: automations.enumerated().map { index, automation in
            (
                automation.id,
                TrackingAutomationEventSource(
                    event: "event-\(index)",
                    tracker: tracker
                ) as any AutomationEventSource
            )
        })

        let triggers = await WorkspaceAutomationRunner.dueAutomationTriggersAsync(
            in: automations,
            now: now,
            eventSources: sources,
            limit: automations.count
        )

        XCTAssertEqual(triggers.map(\.automationID), automations.map(\.id))
        XCTAssertEqual(triggers.map(\.eventDescription), (0..<8).map { "event-\($0)" })
        XCTAssertEqual(tracker.pollCount, automations.count)
        XCTAssertFalse(tracker.observedMainThread)
        XCTAssertGreaterThan(tracker.maximumConcurrentPolls, 1)
        XCTAssertLessThanOrEqual(
            tracker.maximumConcurrentPolls,
            WorkspaceAutomationEventPoller.maximumConcurrentPolls
        )
    }

    func testZeroLimitSkipsEventPolling() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let automation = eventAutomation(index: 0, now: now)
        let tracker = AutomationPollTracker(delay: 0)

        let triggers = await WorkspaceAutomationRunner.dueAutomationTriggersAsync(
            in: [automation],
            now: now,
            eventSources: [
                automation.id: TrackingAutomationEventSource(event: "changed", tracker: tracker)
            ],
            limit: 0
        )

        XCTAssertEqual(triggers, [])
        XCTAssertEqual(tracker.pollCount, 0)
    }

    func testCancellationReturnsWithoutWaitingForBlockingAdapter() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let automation = eventAutomation(index: 0, now: now)
        let gate = BlockingAutomationEventSource(event: "changed")
        defer { gate.release() }

        let pollingTask = Task {
            await WorkspaceAutomationRunner.dueAutomationTriggersAsync(
                in: [automation],
                now: now,
                eventSources: [automation.id: gate],
                limit: 1
            )
        }
        let didStart = await Task.detached {
            gate.waitUntilStarted()
        }.value
        XCTAssertTrue(didStart)

        let cancellationStartedAt = Date()
        pollingTask.cancel()
        let triggers = await pollingTask.value

        XCTAssertEqual(triggers, [])
        XCTAssertLessThan(Date().timeIntervalSince(cancellationStartedAt), 0.5)
    }

    func testChangedAutomationRejectsTriggerResolvedFromOlderSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let automation = eventAutomation(index: 0, now: now)
        let gate = BlockingAutomationEventSource(event: "changed")
        let model = QuillCodeWorkspaceModel()
        model.setAutomations([automation])
        defer { gate.release() }

        let pollingTask = Task {
            await model.runDueAutomationReportsAsync(
                now: now,
                limit: 1,
                eventSources: [automation.id: gate]
            )
        }
        let didStart = await Task.detached {
            gate.waitUntilStarted()
        }.value
        XCTAssertTrue(didStart)
        XCTAssertTrue(model.updateAutomationStatus(id: automation.id, status: .paused))
        gate.release()

        let reports = await pollingTask.value

        XCTAssertEqual(reports, [])
        XCTAssertFalse(model.root.threads.contains { $0.title == "Monitor: Event 0" })
    }

    private func eventAutomation(index: Int, now: Date) -> QuillAutomation {
        QuillAutomation(
            title: "Event \(index)",
            detail: "Watch event \(index).",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "When changed",
            createdAt: now,
            updatedAt: now,
            lastRunAt: now.addingTimeInterval(-1)
        )
    }
}

private final class AutomationPollTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private var activePolls = 0
    private var storedMaximumConcurrentPolls = 0
    private var storedObservedMainThread = false
    private var storedPollCount = 0

    init(delay: TimeInterval) {
        self.delay = delay
    }

    var maximumConcurrentPolls: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedMaximumConcurrentPolls
    }

    var observedMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedObservedMainThread
    }

    var pollCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedPollCount
    }

    func poll(event: String?) -> String? {
        lock.lock()
        activePolls += 1
        storedPollCount += 1
        storedMaximumConcurrentPolls = max(storedMaximumConcurrentPolls, activePolls)
        storedObservedMainThread = storedObservedMainThread || Thread.isMainThread
        lock.unlock()

        Thread.sleep(forTimeInterval: delay)

        lock.lock()
        activePolls -= 1
        lock.unlock()
        return event
    }
}

private struct TrackingAutomationEventSource: AutomationEventSource {
    let event: String?
    let tracker: AutomationPollTracker

    func pendingEvent(since: Date?) -> String? {
        tracker.poll(event: event)
    }
}

private final class BlockingAutomationEventSource: AutomationEventSource, @unchecked Sendable {
    private let event: String?
    private let started = DispatchSemaphore(value: 0)
    private let releaseGate = DispatchSemaphore(value: 0)

    init(event: String?) {
        self.event = event
    }

    func pendingEvent(since: Date?) -> String? {
        started.signal()
        _ = releaseGate.wait(timeout: .now() + 2)
        return event
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + 1) == .success
    }

    func release() {
        releaseGate.signal()
    }
}
