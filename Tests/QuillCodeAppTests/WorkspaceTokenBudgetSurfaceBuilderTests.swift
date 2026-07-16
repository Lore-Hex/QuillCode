import XCTest
@testable import QuillCodeApp
import QuillCodeCore

final class WorkspaceTokenBudgetSurfaceBuilderTests: XCTestCase {
    func testBuildsProviderReportedBudgetAgainstModelContextWindow() throws {
        let thread = ChatThread(
            title: "Work",
            model: "trustedrouter/fast",
            events: [
                ModelTokenUsageEvent.event(usage: ModelTokenUsage(promptTokens: 500, completionTokens: 347))
            ]
        )

        let budget = try XCTUnwrap(
            WorkspaceTokenBudgetSurfaceBuilder(
                thread: thread,
                selectedModelID: "trustedrouter/fast",
                modelCatalog: [model(id: "tr/fast", contextWindowTokens: 128_000)]
            ).surface()
        )

        XCTAssertEqual(budget.usedTokens, 847)
        XCTAssertEqual(budget.limitTokens, 128_000)
        XCTAssertEqual(budget.remainingTokens, 127_153)
        XCTAssertEqual(budget.usedPercent, 1)
        XCTAssertEqual(budget.primaryLabel, "847 / 128k")
        XCTAssertEqual(budget.secondaryLabel, "127.2k left · 1% · ↑500 ↓347 · provider reported")
        XCTAssertEqual(
            budget.detailLabel,
            "Provider reported token budget: 847 used of 128,000 · 127,153 left · 1% used · input 500 · output 347"
        )
        XCTAssertTrue(budget.visibleQuotaLimits.isEmpty)
        XCTAssertNil(budget.quotaSummaryLabel)
    }

    func testEstimatesBudgetBeforeProviderUsageArrives() throws {
        let thread = ChatThread(
            title: "Draft",
            model: "trustedrouter/fast",
            messages: [
                ChatMessage(role: .user, content: String(repeating: "u", count: 76)),
                ChatMessage(role: .assistant, content: String(repeating: "a", count: 76))
            ]
        )

        let budget = try XCTUnwrap(
            WorkspaceTokenBudgetSurfaceBuilder(
                thread: thread,
                selectedModelID: "trustedrouter/fast",
                modelCatalog: [model(id: "trustedrouter/fast", contextWindowTokens: 1_000)]
            ).surface()
        )

        XCTAssertEqual(budget.usedTokens, 50)
        XCTAssertEqual(budget.limitTokens, 1_000)
        XCTAssertEqual(budget.remainingTokens, 950)
        XCTAssertEqual(budget.primaryLabel, "50 / 1k")
        XCTAssertEqual(budget.secondaryLabel, "950 left · 5% · estimated")
        XCTAssertEqual(budget.sourceLabel, "Estimated")
    }

    func testProviderUsageAgainstUnknownWindowShowsHonestUsageOnlyChip() throws {
        // Daily-drive regression: provider-reported usage on a model whose window the catalog
        // does not know was measured against the 32k fallback, inventing "58.4k / 32k · 183% ·
        // 0 left". Unknown window + provider usage ⇒ usage-only chip: real numbers, no limit,
        // no percent, empty progress bar.
        let thread = ChatThread(
            title: "Fallback",
            events: [
                ModelTokenUsageEvent.event(usage: ModelTokenUsage(promptTokens: 58_000, completionTokens: 400))
            ]
        )

        let budget = try XCTUnwrap(
            WorkspaceTokenBudgetSurfaceBuilder(
                thread: thread,
                selectedModelID: "missing/model",
                modelCatalog: []
            ).surface()
        )

        XCTAssertEqual(budget.usedTokens, 58_400)
        XCTAssertEqual(budget.progressPercent, 0)
        XCTAssertEqual(budget.primaryLabel, "58.4k")
        XCTAssertEqual(budget.secondaryLabel, "↑58k ↓400 · window unknown")
        XCTAssertTrue(budget.detailLabel.contains("context window is not in the catalog"), budget.detailLabel)
    }

    func testEstimateModeStillUsesFallbackBudgetWhenCatalogHasNoContextWindow() throws {
        // With NO provider usage yet, the local character estimate against the conservative 32k
        // fallback is unchanged — it is explicitly labeled Estimated.
        let thread = ChatThread(
            title: "Fallback",
            messages: [ChatMessage(role: .user, content: String(repeating: "x", count: 400))]
        )

        let budget = try XCTUnwrap(
            WorkspaceTokenBudgetSurfaceBuilder(
                thread: thread,
                selectedModelID: "missing/model",
                modelCatalog: []
            ).surface()
        )

        XCTAssertEqual(budget.limitTokens, WorkspaceContextBannerBuilder.defaultTokenBudget)
        XCTAssertEqual(budget.sourceLabel, "Estimated")
        XCTAssertTrue(budget.secondaryLabel.hasSuffix("estimated"), budget.secondaryLabel)
    }

    func testCarriesQuotaLimitsWhenRuntimeSuppliesThem() throws {
        let thread = ChatThread(
            title: "Quota",
            model: "trustedrouter/fast",
            events: [
                ModelTokenUsageEvent.event(usage: ModelTokenUsage(promptTokens: 100, completionTokens: 25))
            ]
        )
        let quotas = [
            TokenQuotaLimitSurface(
                periodLabel: "Quota",
                usageLabel: "0 left",
                detailLabel: "Provider rate-limit quota: 0 remaining"
            ),
            TokenQuotaLimitSurface(
                periodLabel: "Reset",
                usageLabel: "2m",
                detailLabel: "Provider rate-limit reset or retry window: 120s"
            ),
        ]

        let budget = try XCTUnwrap(
            WorkspaceTokenBudgetSurfaceBuilder(
                thread: thread,
                selectedModelID: "trustedrouter/fast",
                modelCatalog: [model(id: "trustedrouter/fast", contextWindowTokens: 8_000)],
                quotaLimits: quotas
            ).surface()
        )

        XCTAssertEqual(budget.visibleQuotaLimits, quotas)
        XCTAssertEqual(budget.quotaSummaryLabel, "Quota 0 left · Reset 2m")
        XCTAssertTrue(budget.accessibilityLabel.contains("Quota limits: Quota 0 left · Reset 2m"))
    }

    func testReturnsNilWithoutASelectedThread() {
        let budget = WorkspaceTokenBudgetSurfaceBuilder(
            thread: nil,
            selectedModelID: "trustedrouter/fast",
            modelCatalog: []
        ).surface()

        XCTAssertNil(budget)
    }

    private func model(id: String, contextWindowTokens: Int) -> ModelInfo {
        ModelInfo(
            id: id,
            provider: "TrustedRouter",
            displayName: "Nike 1.0",
            category: "Recommended",
            capabilities: ModelCapabilities(contextWindowTokens: contextWindowTokens)
        )
    }
}
