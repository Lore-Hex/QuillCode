import XCTest
@testable import QuillCodeApp
import QuillCodeCore

final class WorkspaceTokenUsageChipRenderTests: XCTestCase {
    private func makeTopBar(
        usageStatusLabel: String?,
        tokenBudget: TokenBudgetSurface? = nil,
        accountBalance: ProviderAccountBalanceSurface? = nil,
        spendStatusLabel: String? = nil,
        spendStatusDetail: String? = nil
    ) -> TopBarSurface {
        TopBarSurface(
            appName: "QuillCode",
            primaryTitle: "Investigate CI",
            subtitle: "QuillCode - Auto - Nike 1.0",
            instructionLabel: "1 instruction file loaded",
            instructionSources: [],
            memoryLabel: "No memories",
            memorySources: [],
            modelLabel: "Nike 1.0",
            selectedModelID: "trustedrouter/fast",
            modelCategories: [],
            modeLabel: "Auto",
            agentStatus: "Idle",
            computerUseLabel: "Computer Use unavailable",
            showsComputerUseSetup: false,
            usageStatusLabel: usageStatusLabel,
            tokenBudget: tokenBudget,
            accountBalance: accountBalance,
            spendStatusLabel: spendStatusLabel,
            spendStatusDetail: spendStatusDetail
        )
    }

    private func makeTokenBudget(
        usedPercent: Int = 3,
        quotaLimits: [TokenQuotaLimitSurface] = []
    ) -> TokenBudgetSurface {
        TokenBudgetSurface(
            usedTokens: 847,
            limitTokens: 32_000,
            remainingTokens: 31_153,
            usedPercent: usedPercent,
            progressPercent: min(100, max(0, usedPercent)),
            primaryLabel: "847 / 32k",
            secondaryLabel: "31.2k left · \(max(0, usedPercent))% · provider reported",
            detailLabel: "Provider reported token budget: 847 used of 32,000 · 31,153 left · \(max(0, usedPercent))% used",
            sourceLabel: "Provider reported",
            quotaLimits: quotaLimits
        )
    }

    func testTopBarRoundTripsUsageStatusLabel() throws {
        for label in ["847 ctx · ↑500 ↓347", nil] {
            let decoded = try JSONDecoder().decode(
                TopBarSurface.self,
                from: JSONEncoder().encode(makeTopBar(usageStatusLabel: label))
            )
            XCTAssertEqual(decoded.usageStatusLabel, label)
        }
    }

    func testTopBarRoundTripsTokenBudget() throws {
        let topBar = makeTopBar(
            usageStatusLabel: "847 ctx · ↑500 ↓347",
            tokenBudget: makeTokenBudget()
        )

        let decoded = try JSONDecoder().decode(TopBarSurface.self, from: JSONEncoder().encode(topBar))

        XCTAssertEqual(decoded.tokenBudget?.primaryLabel, "847 / 32k")
        XCTAssertEqual(decoded.tokenBudget?.remainingTokens, 31_153)
        XCTAssertEqual(decoded.tokenBudget?.sourceLabel, "Provider reported")
        XCTAssertTrue(decoded.tokenBudget?.visibleQuotaLimits.isEmpty == true)
    }

    func testTopBarRoundTripsAndRendersAccountBalanceSeparatelyFromQuota() throws {
        let accountBalance = ProviderAccountBalanceSurface(
            amountLabel: "$12.50",
            statusLabel: "Balance current",
            detailLabel: "Current TrustedRouter account balance.",
            tone: .normal
        )
        let topBar = makeTopBar(usageStatusLabel: nil, accountBalance: accountBalance)

        let decoded = try JSONDecoder().decode(TopBarSurface.self, from: JSONEncoder().encode(topBar))
        let html = WorkspaceHTMLTopBarRenderer.render(topBar, commands: [])

        XCTAssertEqual(decoded.accountBalance, accountBalance)
        XCTAssertTrue(html.contains(#"data-testid="top-bar-account-balance""#))
        XCTAssertTrue(html.contains("Balance $12.50"))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-token-quota-limits""#))
    }

    func testTopBarRoundTripsTokenBudgetQuotaLimits() throws {
        let topBar = makeTopBar(
            usageStatusLabel: nil,
            tokenBudget: makeTokenBudget(
                quotaLimits: [
                    TokenQuotaLimitSurface(
                        periodLabel: "Day",
                        usageLabel: "12k / 100k",
                        detailLabel: "Daily quota: 12,000 used of 100,000"
                    ),
                    TokenQuotaLimitSurface(
                        periodLabel: "Month",
                        usageLabel: "$2 / $20",
                        detailLabel: "Monthly spend: $2 used of $20"
                    )
                ]
            )
        )

        let decoded = try JSONDecoder().decode(TopBarSurface.self, from: JSONEncoder().encode(topBar))

        XCTAssertEqual(decoded.tokenBudget?.visibleQuotaLimits.map(\.compactLabel), ["Day 12k / 100k", "Month $2 / $20"])
        XCTAssertEqual(decoded.tokenBudget?.quotaSummaryLabel, "Day 12k / 100k · Month $2 / $20")
        XCTAssertEqual(
            decoded.tokenBudget?.accessibilityLabel,
            "Provider reported token budget: 847 used of 32,000 · 31,153 left · 3% used · Quota limits: Day 12k / 100k · Month $2 / $20"
        )
    }

    func testTopBarDecodesLegacyJSONWithoutUsageKey() throws {
        // A persisted top bar from before this field existed must still load (key absent -> nil).
        let encoded = try JSONEncoder().encode(makeTopBar(usageStatusLabel: "847 ctx · ↑500 ↓347"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "usageStatusLabel")
        object.removeValue(forKey: "tokenBudget")
        object.removeValue(forKey: "accountBalance")
        object.removeValue(forKey: "spendStatusLabel")
        object.removeValue(forKey: "spendStatusDetail")
        object.removeValue(forKey: "modelIsLocked")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TopBarSurface.self, from: legacy)
        XCTAssertNil(decoded.usageStatusLabel)
        XCTAssertNil(decoded.tokenBudget)
        XCTAssertNil(decoded.accountBalance)
        XCTAssertNil(decoded.spendStatusLabel)
        XCTAssertNil(decoded.spendStatusDetail)
        XCTAssertFalse(decoded.modelIsLocked, "absent lock key must decode as unlocked (@QuillCodeDefaultFalse)")
    }

    func testHTMLRendererEmitsUsageChipOnlyWhenSet() {
        let withUsage = WorkspaceHTMLTopBarRenderer.render(makeTopBar(usageStatusLabel: "847 ctx · ↑500 ↓347"), commands: [])
        XCTAssertTrue(withUsage.contains(#"data-testid="top-bar-usage""#))
        XCTAssertTrue(withUsage.contains("847 ctx · ↑500 ↓347"))
        XCTAssertTrue(withUsage.contains("topbar-usage-chip"))

        let withoutUsage = WorkspaceHTMLTopBarRenderer.render(makeTopBar(usageStatusLabel: nil), commands: [])
        XCTAssertFalse(withoutUsage.contains(#"data-testid="top-bar-usage""#))
    }

    func testHTMLRendererEmitsTokenBudgetInsteadOfCompactUsage() {
        let html = WorkspaceHTMLTopBarRenderer.render(
            makeTopBar(
                usageStatusLabel: "847 ctx · ↑500 ↓347",
                tokenBudget: makeTokenBudget()
            ),
            commands: []
        )

        XCTAssertTrue(html.contains(#"data-testid="top-bar-token-budget""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-token-budget-primary">847 / 32k"#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-token-budget-secondary">31.2k left · 3%"#))
        XCTAssertTrue(html.contains("Provider reported token budget: 847 used of 32,000 · 31,153 left · 3% used"))
        XCTAssertTrue(html.contains("topbar-token-budget"))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-token-quota-limits""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-usage""#))
    }

    func testHTMLRendererEmitsQuotaLimitsWhenSupplied() {
        let html = WorkspaceHTMLTopBarRenderer.render(
            makeTopBar(
                usageStatusLabel: nil,
                tokenBudget: makeTokenBudget(
                    quotaLimits: [
                        TokenQuotaLimitSurface(
                            periodLabel: "Day",
                            usageLabel: "12k / 100k",
                            detailLabel: "Daily quota: 12,000 used of 100,000"
                        ),
                        TokenQuotaLimitSurface(
                            periodLabel: "Week",
                            usageLabel: "$4 / $50",
                            detailLabel: "Weekly spend: $4 used of $50"
                        )
                    ]
                )
            ),
            commands: []
        )

        XCTAssertTrue(html.contains(#"data-testid="top-bar-token-quota-limits""#))
        XCTAssertTrue(html.contains("Day 12k / 100k"))
        XCTAssertTrue(html.contains("Week $4 / $50"))
        XCTAssertTrue(html.contains("Quota limits: Day 12k / 100k · Week $4 / $50"))
    }

    func testHTMLRendererMarksTokenBudgetWarningAndCriticalTones() {
        let warning = WorkspaceHTMLTopBarRenderer.render(
            makeTopBar(usageStatusLabel: nil, tokenBudget: makeTokenBudget(usedPercent: 80)),
            commands: []
        )
        let critical = WorkspaceHTMLTopBarRenderer.render(
            makeTopBar(usageStatusLabel: nil, tokenBudget: makeTokenBudget(usedPercent: 100)),
            commands: []
        )

        XCTAssertTrue(warning.contains(#"data-tone="warning""#))
        XCTAssertTrue(critical.contains(#"data-tone="critical""#))
    }

    func testHTMLRendererPrefersSpendChipOverUsageChip() {
        let html = WorkspaceHTMLTopBarRenderer.render(
            makeTopBar(
                usageStatusLabel: "1.5k ctx · ↑1k ↓500",
                tokenBudget: makeTokenBudget(),
                spendStatusLabel: "$0.0050 / $1.00",
                spendStatusDetail: "$0.0050 across 1 model call · fuse $1.00. Latest usage: 1.5k ctx · ↑1k ↓500"
            ),
            commands: []
        )

        XCTAssertTrue(html.contains(#"data-testid="top-bar-token-budget""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-spend""#))
        XCTAssertTrue(html.contains("$0.0050 / $1.00"))
        XCTAssertTrue(html.contains("Latest usage: 1.5k ctx · ↑1k ↓500"))
        XCTAssertTrue(html.contains("topbar-spend-chip"))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-usage""#))
    }
}
