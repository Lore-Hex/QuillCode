import XCTest
@testable import QuillCodeCore

final class ThreadPeriodUsageSnapshotTests: XCTestCase {
    func testSnapshotCompactsPeriodUsageWithoutRetainingTranscriptContent() throws {
        let calendar = utcCalendar()
        let retentionStart = date(2026, 8, 1, hour: 0, calendar: calendar)
        let now = date(2026, 8, 12, hour: 12, calendar: calendar)
        var thread = ChatThread(
            title: "Private transcript",
            model: "acme/agent",
            messages: [ChatMessage(role: .user, content: "must never enter the usage cache")]
        )
        thread.events = [
            usageEvent(
                prompt: 9_000,
                completion: 9_000,
                modelID: "acme/agent",
                callCount: 9,
                createdAt: retentionStart.addingTimeInterval(-1)
            ),
            usageEvent(
                prompt: 1_000,
                completion: 500,
                modelID: "acme/agent",
                callCount: 2,
                createdAt: date(2026, 8, 11, hour: 9, calendar: calendar)
            ),
            usageEvent(
                prompt: 2_000,
                completion: 1_000,
                modelID: "acme/agent",
                callCount: 3,
                createdAt: date(2026, 8, 11, hour: 17, calendar: calendar)
            ),
            usageEvent(
                prompt: 500,
                completion: 250,
                modelID: "acme/other",
                callCount: 1,
                createdAt: date(2026, 8, 12, hour: 8, calendar: calendar)
            ),
            usageEvent(
                prompt: 8_000,
                completion: 8_000,
                modelID: "acme/agent",
                callCount: 8,
                createdAt: now.addingTimeInterval(1)
            ),
            ThreadEvent(kind: .notice, summary: "not usage", payloadJSON: "private detail")
        ]

        let snapshot = try XCTUnwrap(ThreadPeriodUsageSnapshot(
            thread: thread,
            retainingSince: retentionStart,
            calendar: calendar,
            now: now
        ))

        XCTAssertEqual(snapshot.events.count, 2)
        let records = try snapshot.events.map {
            try XCTUnwrap(ModelTokenUsageEvent.record(from: $0))
        }
        XCTAssertEqual(records.map(\.callCount), [5, 1])
        XCTAssertEqual(records.map(\.usage.promptTokens), [3_000, 500])
        XCTAssertEqual(records.map(\.usage.completionTokens), [1_500, 250])
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("must never enter"))
        XCTAssertFalse(encoded.contains("private detail"))
    }

    func testDeferredSnapshotPreservesExactPeriodSpendAndCallCounts() throws {
        let calendar = utcCalendar()
        let start = date(2026, 8, 10, hour: 0, calendar: calendar)
        let now = date(2026, 8, 12, hour: 12, calendar: calendar)
        var loaded = ChatThread(
            title: "Usage",
            model: "acme/agent",
            events: [
                usageEvent(
                    prompt: 1_000,
                    completion: 500,
                    modelID: "acme/agent",
                    callCount: 2,
                    createdAt: date(2026, 8, 11, hour: 9, calendar: calendar)
                ),
                usageEvent(
                    prompt: 500,
                    completion: 250,
                    modelID: "acme/other",
                    callCount: 4,
                    createdAt: date(2026, 8, 12, hour: 8, calendar: calendar)
                )
            ]
        )
        let snapshot = try XCTUnwrap(ThreadPeriodUsageSnapshot(
            thread: loaded,
            retainingSince: start,
            calendar: calendar,
            now: now
        ))
        loaded.payloadResidency = .deferred(DeferredThreadPayloadSummary(
            searchText: "",
            periodUsage: snapshot
        ))
        loaded.events = []
        let models = [
            pricedModel(id: "acme/agent"),
            pricedModel(id: "acme/other")
        ]

        let summary = RunSpendPeriodLedger(
            threads: [loaded],
            modelCatalog: models,
            now: now
        ).summary(since: start)

        XCTAssertEqual(summary.pricedCallCount, 6)
        XCTAssertEqual(summary.unpricedCallCount, 0)
        XCTAssertEqual(summary.totalUSD, 0.0075, accuracy: 0.000_001)
    }

    func testSnapshotRejectsUnboundedBucketsAndCalendarChanges() throws {
        let calendar = utcCalendar()
        let now = date(2026, 8, 12, hour: 12, calendar: calendar)
        var thread = ChatThread(model: "acme/agent")
        thread.events = (0...ThreadPeriodUsageSnapshot.maximumBucketCount).map { index in
            usageEvent(
                prompt: 1,
                completion: 0,
                modelID: "acme/model-\(index)",
                callCount: 1,
                createdAt: now
            )
        }
        XCTAssertNil(ThreadPeriodUsageSnapshot(
            thread: thread,
            retainingSince: .distantPast,
            calendar: calendar,
            now: now
        ))

        thread.events = [usageEvent(
            prompt: 1,
            completion: 0,
            modelID: "acme/agent",
            callCount: 1,
            createdAt: now
        )]
        let snapshot = try XCTUnwrap(ThreadPeriodUsageSnapshot(
            thread: thread,
            retainingSince: .distantPast,
            calendar: calendar,
            now: now
        ))
        var changedCalendar = calendar
        changedCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)!
        XCTAssertFalse(snapshot.isCompatible(with: changedCalendar))
    }

    private func usageEvent(
        prompt: Int,
        completion: Int,
        modelID: String,
        callCount: Int,
        createdAt: Date
    ) -> ThreadEvent {
        var event = ModelTokenUsageEvent.event(
            usage: ModelTokenUsage(promptTokens: prompt, completionTokens: completion),
            modelID: modelID,
            callCount: callCount
        )
        event.createdAt = createdAt
        return event
    }

    private func pricedModel(id: String) -> ModelInfo {
        ModelInfo(
            id: id,
            provider: "acme",
            displayName: id,
            category: "Custom",
            capabilities: ModelCapabilities(
                inputPricePerMillionTokens: 2,
                outputPricePerMillionTokens: 6
            )
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
