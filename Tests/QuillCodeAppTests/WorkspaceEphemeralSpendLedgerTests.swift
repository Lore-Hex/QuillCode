import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceEphemeralSpendLedgerTests: XCTestCase {
    func testTenThousandDestroyedSessionsCompactToOneDayModelReceipt() throws {
        let calendar = utcCalendar()
        let now = date(2026, 8, 7, hour: 12, calendar: calendar)
        var ledger = WorkspaceEphemeralSpendLedger()

        for _ in 0..<10_000 {
            let thread = ephemeralThread(
                modelID: "acme/agent",
                usage: ModelTokenUsage(promptTokens: 1, completionTokens: 2),
                createdAt: now,
                secret: "must never survive"
            )
            ledger.retain(thread, calendar: calendar, now: now)
        }

        let receiptThread = try XCTUnwrap(ledger.periodThreads(calendar: calendar, now: now).first)
        let record = try XCTUnwrap(receiptThread.events.first.flatMap(ModelTokenUsageEvent.record(from:)))
        XCTAssertEqual(ledger.bucketCount, 1)
        XCTAssertEqual(receiptThread.events.count, 1)
        XCTAssertTrue(receiptThread.messages.isEmpty)
        XCTAssertEqual(record.callCount, 10_000)
        XCTAssertEqual(record.usage.promptTokens, 10_000)
        XCTAssertEqual(record.usage.completionTokens, 20_000)
        XCTAssertEqual(record.usage.totalTokens, 30_000)
    }

    func testCompactionPreservesDailyModelBucketsSpendAndCallCounts() throws {
        let calendar = utcCalendar()
        let yesterday = date(2026, 8, 6, hour: 18, calendar: calendar)
        let now = date(2026, 8, 7, hour: 12, calendar: calendar)
        var ledger = WorkspaceEphemeralSpendLedger()

        ledger.retain(ephemeralThread(
            modelID: "acme/agent",
            usage: ModelTokenUsage(promptTokens: 1_000, completionTokens: 500),
            createdAt: yesterday
        ), calendar: calendar, now: now)
        for modelID in ["acme/agent", "acme/agent", "acme/other"] {
            ledger.retain(ephemeralThread(
                modelID: modelID,
                usage: ModelTokenUsage(promptTokens: 1_000, completionTokens: 500),
                createdAt: now
            ), calendar: calendar, now: now)
        }

        let threads = ledger.periodThreads(calendar: calendar, now: now)
        let summary = RunSpendPeriodLedger(
            threads: threads,
            modelCatalog: pricedModels(),
            now: now
        ).summary(since: calendar.startOfDay(for: now))

        XCTAssertEqual(ledger.bucketCount, 3)
        XCTAssertEqual(threads.first?.events.count, 3)
        XCTAssertEqual(summary.pricedCallCount, 3)
        XCTAssertEqual(summary.unpricedCallCount, 0)
        XCTAssertEqual(summary.totalUSD, 0.015, accuracy: 0.000_001)
    }

    func testMonthRolloverKeepsTheOverlappingWeekThenReleasesIt() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let january = date(2026, 1, 31, hour: 23, calendar: calendar)
        let february = date(2026, 2, 1, hour: 1, calendar: calendar)
        let nextWeek = date(2026, 2, 2, hour: 1, calendar: calendar)
        var ledger = WorkspaceEphemeralSpendLedger()
        ledger.retain(ephemeralThread(
            modelID: "acme/agent",
            usage: ModelTokenUsage(promptTokens: 1_000),
            createdAt: january
        ), calendar: calendar, now: january)

        XCTAssertEqual(ledger.bucketCount, 1)
        let overlappingWeek = ledger.periodThreads(calendar: calendar, now: february)
        let weeklySummary = RunSpendPeriodLedger(
            threads: overlappingWeek,
            modelCatalog: pricedModels(),
            now: february
        ).summary(since: try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: february)?.start))
        XCTAssertEqual(weeklySummary.pricedCallCount, 1)
        XCTAssertEqual(ledger.bucketCount, 1)

        XCTAssertTrue(ledger.periodThreads(calendar: calendar, now: nextWeek).isEmpty)
        XCTAssertEqual(ledger.bucketCount, 0)
    }

    func testIgnoresDurableThreadsAndNonUsageEvents() {
        let calendar = utcCalendar()
        let now = date(2026, 8, 7, hour: 12, calendar: calendar)
        var durable = ChatThread(
            title: "Durable",
            messages: [.init(role: .user, content: "ordinary transcript")],
            events: [ModelTokenUsageEvent.event(usage: ModelTokenUsage(promptTokens: 500))]
        )
        durable.events[0].createdAt = now
        var ephemeral = ChatThread(
            title: "Side",
            events: [ThreadEvent(kind: .notice, createdAt: now, summary: "No usage")],
            runtimeContext: .sideConversation(parentThreadID: durable.id)
        )
        ephemeral.messages = [.init(role: .user, content: "private transcript")]
        var ledger = WorkspaceEphemeralSpendLedger()

        ledger.retain(durable, calendar: calendar, now: now)
        ledger.retain(ephemeral, calendar: calendar, now: now)

        XCTAssertTrue(ledger.isEmpty)
        XCTAssertTrue(ledger.periodThreads(calendar: calendar, now: now).isEmpty)
    }

    private func ephemeralThread(
        modelID: String,
        usage: ModelTokenUsage,
        createdAt: Date,
        secret: String = ""
    ) -> ChatThread {
        var event = ModelTokenUsageEvent.event(usage: usage, modelID: modelID)
        event.createdAt = createdAt
        return ChatThread(
            title: "Side",
            model: modelID,
            messages: secret.isEmpty ? [] : [.init(role: .user, content: secret)],
            events: [event],
            runtimeContext: .sideConversation(parentThreadID: UUID())
        )
    }

    private func pricedModels() -> [ModelInfo] {
        ["acme/agent", "acme/other"].map { modelID in
            ModelInfo(
                id: modelID,
                provider: "acme",
                displayName: modelID,
                category: "Custom",
                capabilities: ModelCapabilities(
                    inputPricePerMillionTokens: 2,
                    outputPricePerMillionTokens: 6
                )
            )
        }
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
