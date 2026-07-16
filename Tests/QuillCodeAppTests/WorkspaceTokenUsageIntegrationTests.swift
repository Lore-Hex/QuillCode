import XCTest
@testable import QuillCodeApp
import QuillCodeCore

@MainActor
final class WorkspaceTokenUsageIntegrationTests: XCTestCase {
    private func usageEvent(prompt: Int, completion: Int) -> ThreadEvent {
        ModelTokenUsageEvent.event(usage: ModelTokenUsage(promptTokens: prompt, completionTokens: completion))
    }

    private func usageEvent(prompt: Int, completion: Int, modelID: String) -> ThreadEvent {
        ModelTokenUsageEvent.event(
            usage: ModelTokenUsage(promptTokens: prompt, completionTokens: completion),
            modelID: modelID
        )
    }

    private func usageEvent(prompt: Int, completion: Int, modelID: String, createdAt: Date) throws -> ThreadEvent {
        ThreadEvent(
            kind: .notice,
            createdAt: createdAt,
            summary: ModelTokenUsageEvent.summary,
            payloadJSON: try JSONHelpers.encodePretty(ModelTokenUsageRecord(
                usage: ModelTokenUsage(promptTokens: prompt, completionTokens: completion),
                modelID: modelID
            ))
        )
    }

    private func pricedModelCatalog() -> [ModelInfo] {
        [
            ModelInfo(
                id: "acme/agent",
                provider: "acme",
                displayName: "Acme Agent",
                category: "Custom",
                capabilities: ModelCapabilities(
                    inputPricePerMillionTokens: 2.0,
                    outputPricePerMillionTokens: 6.0
                )
            )
        ]
    }

    func testUsageChipReflectsLatestProviderUsageOfSelectedThread() {
        let thread = ChatThread(title: "Work", events: [usageEvent(prompt: 500, completion: 347)])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        let topBar = model.surface().topBar

        XCTAssertEqual(topBar.usageStatusLabel, "847 ctx · ↑500 ↓347")
        // Provider usage with no catalog window: the honest usage-only chip (no invented "/ 32k").
        XCTAssertEqual(topBar.tokenBudget?.primaryLabel, "847")
        XCTAssertEqual(topBar.tokenBudget?.secondaryLabel, "↑500 ↓347 · window unknown")
    }

    func testUsesTheMostRecentUsageEvent() {
        let thread = ChatThread(title: "Work", events: [
            usageEvent(prompt: 100, completion: 50),
            usageEvent(prompt: 900, completion: 600)
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        let topBar = model.surface().topBar

        XCTAssertEqual(topBar.usageStatusLabel, "1.5k ctx · ↑900 ↓600")
        XCTAssertEqual(topBar.tokenBudget?.primaryLabel, "1.5k")
    }

    func testNoUsageChipWithoutAUsageEvent() {
        let thread = ChatThread(title: "Fresh")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        let topBar = model.surface().topBar

        XCTAssertNil(topBar.usageStatusLabel)
        XCTAssertEqual(topBar.tokenBudget?.primaryLabel, "0 / 32k")
        XCTAssertEqual(topBar.tokenBudget?.secondaryLabel, "32k left · 0% · estimated")
    }

    func testUsageChipIsDerivedPerThreadAndDoesNotBleed() {
        let used = ChatThread(title: "Used", events: [usageEvent(prompt: 100, completion: 50)])
        let fresh = ChatThread(title: "Fresh")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [used, fresh], selectedThreadID: used.id)
        )
        XCTAssertEqual(model.surface().topBar.usageStatusLabel, "150 ctx · ↑100 ↓50")
        XCTAssertEqual(model.surface().topBar.tokenBudget?.primaryLabel, "150")

        // Selecting the fresh thread shows no usage even though another thread has it.
        model.selectThread(fresh.id)
        XCTAssertNil(model.surface().topBar.usageStatusLabel)
        XCTAssertEqual(model.surface().topBar.tokenBudget?.primaryLabel, "0 / 32k")
    }

    func testActivityShowsPricedRunReceiptsFromModelCatalog() throws {
        let thread = ChatThread(
            title: "Costed run",
            events: [usageEvent(prompt: 1_000, completion: 500, modelID: "acme/agent")]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                config: AppConfig(runSpendFuseUSD: 1.0),
                threads: [thread],
                selectedThreadID: thread.id,
                modelCatalog: pricedModelCatalog()
            ),
            activity: ActivityState(isVisible: true)
        )

        let receipts = model.surface().activity.runReceiptItems
        let section = try XCTUnwrap(model.surface().activity.sections.first { $0.kind == .runReceipts })
        let topBar = model.surface().topBar

        XCTAssertEqual(receipts.map(\.title), ["Thread spend", "Acme Agent"])
        XCTAssertEqual(receipts.first?.detail, "$0.0050 across 1 model call · fuse $1.00")
        XCTAssertEqual(receipts.first?.statusLabel, "Within fuse")
        XCTAssertEqual(
            receipts.last?.detail,
            "acme/agent · 1.5k ctx · ↑1k ↓500 · $0.0050 (in $0.0020, out $0.0030)"
        )
        XCTAssertEqual(receipts.last?.statusLabel, "Logged")
        XCTAssertEqual(section.title, "Run Receipts")
        XCTAssertEqual(section.itemTestID, "activity-run-receipt")
        XCTAssertEqual(section.countLabel, "2 items")
        XCTAssertEqual(topBar.spendStatusLabel, "$0.0050 / $1.00")
        XCTAssertEqual(
            topBar.spendStatusDetail,
            "$0.0050 across 1 model call · fuse $1.00. Latest usage: 1.5k ctx · ↑1k ↓500"
        )
        XCTAssertNil(topBar.usageStatusLabel)
        // acme/agent has prices but no context window in the catalog: honest usage-only chip.
        XCTAssertEqual(topBar.tokenBudget?.primaryLabel, "1.5k")
        XCTAssertEqual(topBar.tokenBudget?.secondaryLabel, "↑1k ↓500 · window unknown")
    }

    func testActivityRunReceiptsFlagSpendFuseCrossing() {
        let thread = ChatThread(
            title: "Costed run",
            events: [usageEvent(prompt: 2_000, completion: 1_000, modelID: "acme/agent")]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                config: AppConfig(runSpendFuseUSD: 0.01),
                threads: [thread],
                selectedThreadID: thread.id,
                modelCatalog: pricedModelCatalog()
            ),
            activity: ActivityState(isVisible: true)
        )

        let summary = model.surface().activity.runReceiptItems.first

        XCTAssertEqual(summary?.detail, "$0.01 across 1 model call · fuse $0.01")
        XCTAssertEqual(summary?.statusLabel, "Review")
    }

    func testRunReceiptLedgerUsesFirstCatalogMatchWhenCatalogHasDuplicateAliases() {
        let thread = ChatThread(
            title: "Costed run",
            events: [usageEvent(prompt: 1_000, completion: 0, modelID: "trustedrouter/fast")]
        )

        let ledger = RunSpendLedger(
            thread: thread,
            modelCatalog: [
                ModelInfo(
                    id: "tr/fast",
                    provider: "TrustedRouter",
                    displayName: "Nike 1.0",
                    category: "Fast",
                    capabilities: ModelCapabilities(
                        inputPricePerMillionTokens: 1.0,
                        outputPricePerMillionTokens: 1.0
                    )
                ),
                ModelInfo(
                    id: "trustedrouter/fast",
                    provider: "TrustedRouter",
                    displayName: "Duplicate Nike",
                    category: "Fast",
                    capabilities: ModelCapabilities(
                        inputPricePerMillionTokens: 100.0,
                        outputPricePerMillionTokens: 100.0
                    )
                )
            ],
            fuseUSD: 0.01
        )

        XCTAssertEqual(ledger.receipts.first?.modelName, "Nike 1.0")
        XCTAssertEqual(ledger.totalUSD, 0.001, accuracy: 0.000001)
        XCTAssertFalse(ledger.blocksNextRun)
    }

    func testSpendHistoryQuotaBuilderBucketsPricedReceiptsByLocalPeriod() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_735_257_600) // 2024-12-27 00:00:00 UTC.
        let yesterday = now.addingTimeInterval(-86_400)
        let lastMonth = now.addingTimeInterval(-35 * 86_400)
        let current = ChatThread(title: "Today", events: [
            try usageEvent(prompt: 1_000, completion: 500, modelID: "acme/agent", createdAt: now)
        ])
        let older = ChatThread(title: "Earlier", events: [
            try usageEvent(prompt: 2_000, completion: 0, modelID: "acme/agent", createdAt: yesterday),
            try usageEvent(prompt: 9_000, completion: 9_000, modelID: "acme/agent", createdAt: lastMonth)
        ])

        let rows = WorkspaceSpendHistoryQuotaBuilder(
            threads: [current, older],
            modelCatalog: pricedModelCatalog(),
            calendar: calendar,
            now: now
        ).quotaLimits()

        XCTAssertEqual(rows.map(\.compactLabel), [
            "Today $0.0050",
            "Week $0.0090",
            "Month $0.0090"
        ])
        XCTAssertEqual(rows.last?.detailLabel, "Local priced model spend month: $0.0090")
    }

    func testSpendHistoryQuotaBuilderRendersConfiguredCapsAtZeroSpend() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_735_257_600)

        let rows = WorkspaceSpendHistoryQuotaBuilder(
            threads: [],
            modelCatalog: pricedModelCatalog(),
            periodLimits: RunSpendPeriodLimits(dailyUSD: 1, weeklyUSD: 5, monthlyUSD: 20),
            calendar: calendar,
            now: now
        ).quotaLimits()

        XCTAssertEqual(rows.map(\.compactLabel), [
            "Today $0.00 / $1.00",
            "Week $0.00 / $5.00",
            "Month $0.00 / $20.00"
        ])
        XCTAssertEqual(rows.first?.detailLabel, "Local priced model spend today: $0.00 of $1.00 · 0% used")
    }

    func testSpendHistoryQuotaBuilderRendersConfiguredCapsWithUsagePercent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_735_257_600)
        let current = ChatThread(title: "Today", events: [
            try usageEvent(prompt: 1_000, completion: 500, modelID: "acme/agent", createdAt: now)
        ])

        let rows = WorkspaceSpendHistoryQuotaBuilder(
            threads: [current],
            modelCatalog: pricedModelCatalog(),
            periodLimits: RunSpendPeriodLimits(dailyUSD: 0.01),
            calendar: calendar,
            now: now
        ).quotaLimits()

        XCTAssertEqual(rows.map(\.compactLabel), [
            "Today $0.0050 / $0.01",
            "Week $0.0050",
            "Month $0.0050"
        ])
        XCTAssertEqual(rows.first?.detailLabel, "Local priced model spend today: $0.0050 of $0.01 · 50% used")
    }

    func testTopBarShowsLocalDayWeekMonthSpendHistoryRows() throws {
        let now = Date()
        let current = ChatThread(title: "Costed run", events: [
            try usageEvent(prompt: 1_000, completion: 500, modelID: "acme/agent", createdAt: now)
        ])
        let other = ChatThread(title: "Other costed run", events: [
            try usageEvent(prompt: 500, completion: 0, modelID: "acme/agent", createdAt: now)
        ])
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [current, other],
                selectedThreadID: current.id,
                modelCatalog: pricedModelCatalog()
            )
        )

        let quotaRows = try XCTUnwrap(model.surface().topBar.tokenBudget?.visibleQuotaLimits)

        XCTAssertEqual(quotaRows.map(\.periodLabel), ["Today", "Week", "Month"])
        XCTAssertEqual(quotaRows.map(\.usageLabel), ["$0.0060", "$0.0060", "$0.0060"])
        XCTAssertEqual(
            model.surface().topBar.tokenBudget?.quotaSummaryLabel,
            "Today $0.0060 · Week $0.0060 · Month $0.0060"
        )
    }

    func testTopBarShowsConfiguredSpendLimitRowsBeforeAnySpend() throws {
        let current = ChatThread(title: "Fresh")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                config: AppConfig(
                    runSpendPeriodLimits: RunSpendPeriodLimits(dailyUSD: 1, weeklyUSD: 5, monthlyUSD: 20)
                ),
                threads: [current],
                selectedThreadID: current.id,
                modelCatalog: pricedModelCatalog()
            )
        )

        let quotaRows = try XCTUnwrap(model.surface().topBar.tokenBudget?.visibleQuotaLimits)

        XCTAssertEqual(quotaRows.map(\.periodLabel), ["Today", "Week", "Month"])
        XCTAssertEqual(quotaRows.map(\.usageLabel), ["$0.00 / $1.00", "$0.00 / $5.00", "$0.00 / $20.00"])
        XCTAssertEqual(
            model.surface().topBar.tokenBudget?.quotaSummaryLabel,
            "Today $0.00 / $1.00 · Week $0.00 / $5.00 · Month $0.00 / $20.00"
        )
    }

    func testActivityRunReceiptsKeepLegacyUnpricedUsageAuditable() throws {
        let legacyUsage = ModelTokenUsage(promptTokens: 100, completionTokens: 25)
        let legacyEvent = ThreadEvent(
            kind: .notice,
            summary: ModelTokenUsageEvent.summary,
            payloadJSON: try JSONHelpers.encodePretty(legacyUsage)
        )
        let thread = ChatThread(
            title: "Legacy run",
            model: "unknown/model",
            events: [legacyEvent]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let receipts = model.surface().activity.runReceiptItems

        XCTAssertEqual(receipts.first?.detail, "Unpriced across 1 model call · 1 unpriced · fuse $1.00")
        XCTAssertEqual(receipts.first?.statusLabel, "Partial")
        XCTAssertEqual(receipts.last?.title, "unknown/model")
        XCTAssertEqual(receipts.last?.statusLabel, "Unpriced")
    }
}
