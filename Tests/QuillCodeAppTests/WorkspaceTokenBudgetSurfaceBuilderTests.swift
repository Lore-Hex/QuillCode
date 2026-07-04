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
        XCTAssertEqual(budget.primaryLabel, "847 / 128k tokens")
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
        XCTAssertEqual(budget.primaryLabel, "50 / 1k tokens")
        XCTAssertEqual(budget.secondaryLabel, "950 left · 5% · estimated")
        XCTAssertEqual(budget.sourceLabel, "Estimated")
    }

    func testUsesFallbackBudgetWhenCatalogHasNoContextWindow() throws {
        let thread = ChatThread(
            title: "Fallback",
            events: [
                ModelTokenUsageEvent.event(usage: ModelTokenUsage(promptTokens: 12, completionTokens: 8))
            ]
        )

        let budget = try XCTUnwrap(
            WorkspaceTokenBudgetSurfaceBuilder(
                thread: thread,
                selectedModelID: "missing/model",
                modelCatalog: []
            ).surface()
        )

        XCTAssertEqual(budget.limitTokens, WorkspaceContextBannerBuilder.defaultTokenBudget)
        XCTAssertEqual(budget.primaryLabel, "20 / 32k tokens")
        XCTAssertEqual(budget.secondaryLabel, "32k left · 0% · ↑12 ↓8 · provider reported")
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
