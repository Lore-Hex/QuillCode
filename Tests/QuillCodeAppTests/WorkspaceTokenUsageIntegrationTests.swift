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

    func testUsageChipReflectsLatestProviderUsageOfSelectedThread() {
        let thread = ChatThread(title: "Work", events: [usageEvent(prompt: 500, completion: 347)])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        XCTAssertEqual(model.surface().topBar.usageStatusLabel, "847 ctx · ↑500 ↓347")
    }

    func testUsesTheMostRecentUsageEvent() {
        let thread = ChatThread(title: "Work", events: [
            usageEvent(prompt: 100, completion: 50),
            usageEvent(prompt: 900, completion: 600)
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        XCTAssertEqual(model.surface().topBar.usageStatusLabel, "1.5k ctx · ↑900 ↓600")
    }

    func testNoUsageChipWithoutAUsageEvent() {
        let thread = ChatThread(title: "Fresh")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        XCTAssertNil(model.surface().topBar.usageStatusLabel)
    }

    func testUsageChipIsDerivedPerThreadAndDoesNotBleed() {
        let used = ChatThread(title: "Used", events: [usageEvent(prompt: 100, completion: 50)])
        let fresh = ChatThread(title: "Fresh")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [used, fresh], selectedThreadID: used.id)
        )
        XCTAssertEqual(model.surface().topBar.usageStatusLabel, "150 ctx · ↑100 ↓50")

        // Selecting the fresh thread shows no usage even though another thread has it.
        model.selectThread(fresh.id)
        XCTAssertNil(model.surface().topBar.usageStatusLabel)
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
                modelCatalog: [
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
        XCTAssertEqual(topBar.spendStatusLabel, "Spend $0.0050 / $1.00")
        XCTAssertEqual(
            topBar.spendStatusDetail,
            "$0.0050 across 1 model call · fuse $1.00. Latest usage: 1.5k ctx · ↑1k ↓500"
        )
        XCTAssertNil(topBar.usageStatusLabel)
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
                modelCatalog: [
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
