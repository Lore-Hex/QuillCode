import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class JSONAutomationStoreTests: PersistenceTestCase {
    func testAutomationStoreRoundTripsSortedByStatusAndNextRun() throws {
        let store = try makeAutomationStore()
        let paused = QuillAutomation(
            title: "Paused monitor",
            detail: "Watch later.",
            kind: .monitor,
            status: .paused,
            scheduleKind: .event,
            scheduleDescription: "Event",
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let later = QuillAutomation(
            title: "Later",
            detail: "Run later.",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: "Daily",
            updatedAt: Date(timeIntervalSince1970: 2),
            nextRunAt: Date(timeIntervalSince1970: 20),
            recurrence: QuillAutomationRecurrence(interval: 1, unit: .days)
        )
        let sooner = QuillAutomation(
            title: "Sooner",
            detail: "Run soon.",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            scheduleDescription: "In 10 minutes",
            updatedAt: Date(timeIntervalSince1970: 1),
            nextRunAt: Date(timeIntervalSince1970: 10)
        )

        try store.save([paused, later, sooner])

        XCTAssertEqual(try store.load().map(\.title), ["Sooner", "Later", "Paused monitor"])
        XCTAssertEqual(
            try store.load().first { $0.title == "Later" }?.recurrence,
            QuillAutomationRecurrence(interval: 1, unit: .days)
        )
    }

    func testAutomationStoreRoundTripsEventSource() throws {
        let store = try makeAutomationStore()
        let fileAutomation = QuillAutomation(
            title: "Watch logs",
            detail: "Summarize watched file changes.",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "File changes",
            eventSource: QuillAutomationEventSource(kind: .fileChange, path: "logs/watch.txt"),
            updatedAt: Date(timeIntervalSince1970: 1),
            lastRunAt: Date(timeIntervalSince1970: 2)
        )
        let urlAutomation = QuillAutomation(
            title: "Watch status page",
            detail: "Check when release notes change.",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "URL Last-Modified",
            eventSource: QuillAutomationEventSource(
                kind: .urlLastModified,
                path: "https://example.com/releases"
            ),
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let feedAutomation = QuillAutomation(
            title: "Watch release feed",
            detail: "Check when the feed publishes a new entry.",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "URL feed update",
            eventSource: QuillAutomationEventSource(
                kind: .urlFeedUpdate,
                path: "https://example.com/feed.xml"
            ),
            updatedAt: Date(timeIntervalSince1970: 4)
        )

        try store.save([fileAutomation, urlAutomation, feedAutomation])

        let loaded = try store.load()
        XCTAssertTrue(loaded.contains { automation in
            automation.eventSource == fileAutomation.eventSource
                && automation.eventSource?.kind == .fileChange
                && automation.eventSource?.path == "logs/watch.txt"
        })
        XCTAssertTrue(loaded.contains { automation in
            automation.eventSource == urlAutomation.eventSource
                && automation.eventSource?.kind == .urlLastModified
                && automation.eventSource?.path == "https://example.com/releases"
        })
        XCTAssertTrue(loaded.contains { automation in
            automation.eventSource == feedAutomation.eventSource
                && automation.eventSource?.kind == .urlFeedUpdate
                && automation.eventSource?.path == "https://example.com/feed.xml"
        })
    }

    func testAutomationStoreReturnsEmptyListWhenMissing() throws {
        let store = try makeAutomationStore()

        XCTAssertEqual(try store.load(), [])
    }
}

private extension JSONAutomationStoreTests {
    func makeAutomationStore() throws -> JSONAutomationStore {
        try JSONAutomationStore(fileURL: makeTempDirectory().appendingPathComponent("automations.json"))
    }
}
