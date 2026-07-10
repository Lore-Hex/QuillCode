import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeTopBarSurfaceTests: XCTestCase {
    func testModelPickerEmptyStateExplainsBundledCatalogScope() {
        let copy = ModelPickerEmptyStateCopy.copy(
            query: "minimax",
            catalogSource: .bundled,
            catalogStatusDetail: "Using built-in recommended models."
        )

        XCTAssertEqual(copy.title, "No bundled model matches")
        XCTAssertTrue(copy.detail.contains("Sign in or refresh TrustedRouter"))
        XCTAssertTrue(copy.detail.contains("\"minimax\""))
        XCTAssertEqual(copy.footnote, "Using built-in recommended models.")
    }

    func testModelPickerEmptyStateExplainsRefreshFallback() {
        let copy = ModelPickerEmptyStateCopy.copy(
            query: "claude",
            catalogSource: .fallbackAfterFailure,
            catalogStatusDetail: "The latest TrustedRouter model refresh failed: offline"
        )

        XCTAssertEqual(copy.title, "No fallback model matches")
        XCTAssertTrue(copy.detail.contains("last TrustedRouter refresh failed"))
        XCTAssertTrue(copy.detail.contains("\"claude\""))
        XCTAssertEqual(copy.footnote, "The latest TrustedRouter model refresh failed: offline")
    }

    func testModelPickerEmptyStateUsesPlainSearchHintForLiveCatalog() {
        let copy = ModelPickerEmptyStateCopy.copy(
            query: "unknown",
            catalogSource: .liveTrustedRouter,
            catalogStatusDetail: nil
        )

        XCTAssertEqual(copy.title, "No TrustedRouter model matches")
        XCTAssertEqual(copy.detail, "Try a provider, category, model name, capability, or state.")
        XCTAssertNil(copy.footnote)
    }

    func testTopBarFiltersModelCategoriesByMetadataFavoritesAndRecents() {
        let topBar = TopBarSurface(
            appName: "QuillCode",
            primaryTitle: "Project",
            subtitle: "Ready",
            instructionLabel: "Instructions",
            instructionSources: [],
            memoryLabel: "Memory",
            memorySources: [],
            modelLabel: TrustedRouterDefaults.prometheusModelDisplayName,
            selectedModelID: TrustedRouterDefaults.prometheusModel,
            modelCategories: [
                ModelCategorySurface(category: "Favorites", models: [
                    modelOption(
                        id: TrustedRouterDefaults.prometheusModel,
                        provider: TrustedRouterDefaults.trustedRouterProvider,
                        displayName: TrustedRouterDefaults.prometheusModelDisplayName,
                        category: "Recommended",
                        isFavorite: true,
                        badges: ["Favorite", "Current", "Recommended"]
                    )
                ]),
                ModelCategorySurface(category: "Recent", models: [
                    modelOption(
                        id: "moonshotai/kimi-k2.6",
                        provider: "moonshotai",
                        displayName: "Kimi K2.6",
                        category: "Safety",
                        badges: ["Recent"]
                    )
                ]),
                ModelCategorySurface(category: "Coding", models: [
                    modelOption(
                        id: "acme/code-pro",
                        provider: "acme",
                        displayName: "Code Pro",
                        category: "Coding"
                    )
                ])
            ],
            modeLabel: "Auto",
            agentStatus: "Idle",
            computerUseLabel: "Computer Use Ready",
            showsComputerUseSetup: false
        )

        XCTAssertEqual(topBar.filteredModelCategories(matching: "").map(\.category), ["Favorites", "Recent", "Coding"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "favorite").map(\.category), ["Favorites"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "recent").map(\.category), ["Recent"])
        XCTAssertEqual(filteredModelIDs(topBar, query: "favorite prometheus"), [TrustedRouterDefaults.prometheusModel])
        XCTAssertEqual(filteredModelIDs(topBar, query: "recent moon k2"), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(filteredModelIDs(topBar, query: "coding"), ["acme/code-pro"])
        XCTAssertTrue(topBar.filteredModelCategories(matching: "does-not-exist").isEmpty)
    }

    func testTopBarSummarizesFilteredModelScope() {
        let topBar = TopBarSurface(
            appName: "QuillCode",
            primaryTitle: "Project",
            subtitle: "Ready",
            instructionLabel: "Instructions",
            instructionSources: [],
            memoryLabel: "Memory",
            memorySources: [],
            modelLabel: TrustedRouterDefaults.fastModelDisplayName,
            selectedModelID: TrustedRouterDefaults.defaultModel,
            modelCategories: [
                ModelCategorySurface(category: "Coding", models: [
                    modelOption(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
                    modelOption(id: "deepseek/deepseek-v4-flash", provider: "deepseek", displayName: "DeepSeek V4 Flash", category: "Coding")
                ]),
                ModelCategorySurface(category: "Research", models: [
                    modelOption(id: "moonshotai/kimi-k2.6", provider: "moonshotai", displayName: "Kimi K2.6", category: "Research")
                ]),
                ModelCategorySurface(category: "Vision", models: [
                    modelOption(id: "minimax/vision", provider: "minimax", displayName: "MiniMax Vision", category: "Vision")
                ]),
                ModelCategorySurface(category: "Audio", models: [
                    modelOption(id: "z-ai/audio", provider: "z-ai", displayName: "Z Audio", category: "Audio")
                ])
            ],
            modeLabel: "Auto",
            agentStatus: "Idle",
            computerUseLabel: "Computer Use Ready",
            showsComputerUseSetup: false
        )

        XCTAssertEqual(
            topBar.filteredModelScopeSummary(matching: ""),
            "Categories: Coding, Research, Vision +1 more · Providers: acme, deepseek, moonshotai +2 more"
        )
        XCTAssertEqual(
            topBar.filteredModelScopeSummary(matching: "deepseekv4flash"),
            "Categories: Coding · Providers: deepseek"
        )
        XCTAssertNil(topBar.filteredModelScopeSummary(matching: "does-not-exist"))
    }

    func testHTMLTopBarRendersLiveWorkChip() {
        let topBar = TopBarSurface(
            appName: "QuillCode",
            primaryTitle: "Project",
            subtitle: "Ready",
            instructionLabel: "Instructions",
            instructionSources: [],
            memoryLabel: "Memory",
            memorySources: [],
            modelLabel: TrustedRouterDefaults.fastModelDisplayName,
            selectedModelID: TrustedRouterDefaults.defaultModel,
            modelCategories: [],
            modeLabel: "Auto",
            agentStatus: "Running",
            liveWork: TopBarLiveWorkSurface(
                label: "Running Shell command",
                detail: "Current work: 1 running. Focus: Shell command: swift test. Active tools: Shell command.",
                tone: .running
            ),
            computerUseLabel: "Computer Use Ready",
            showsComputerUseSetup: false
        )

        let html = WorkspaceHTMLTopBarRenderer.render(topBar, commands: [])

        XCTAssertTrue(html.contains(#"data-testid="top-bar-live-work""#))
        XCTAssertTrue(html.contains(#"data-tone="running""#))
        XCTAssertTrue(html.contains("Running Shell command"))
        XCTAssertTrue(html.contains("Current work: 1 running"))
    }

    func testModelCategorySearchFilterNormalizesWhitespaceAndHidesSpecialCategories() {
        let categories = [
            ModelCategorySurface(category: "Favorites", models: [
                modelOption(
                    id: TrustedRouterDefaults.defaultModel,
                    provider: TrustedRouterDefaults.trustedRouterProvider,
                    displayName: TrustedRouterDefaults.fastModelDisplayName,
                    category: "Recommended",
                    isFavorite: true,
                    badges: ["Favorite"]
                )
            ]),
            ModelCategorySurface(category: "Recent", models: [
                modelOption(
                    id: TrustedRouterDefaults.prometheusModel,
                    provider: TrustedRouterDefaults.trustedRouterProvider,
                    displayName: TrustedRouterDefaults.prometheusModelDisplayName,
                    category: "Recommended",
                    badges: ["Recent"]
                )
            ]),
            ModelCategorySurface(category: "Coding", models: [
                modelOption(
                    id: "acme/code-pro",
                    provider: "acme",
                    displayName: "Code Pro",
                    category: "Coding",
                    badges: ["Tool calling"]
                ),
                modelOption(
                    id: "acme/chat-lite",
                    provider: "acme",
                    displayName: "Chat Lite",
                    category: "General"
                )
            ])
        ]

        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "  CODE    PRO  ").flatMap(\.models).map(\.id),
            ["acme/code-pro"]
        )
        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "recommended").map(\.category),
            []
        )
        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "favorites nike").flatMap(\.models).map(\.id),
            [TrustedRouterDefaults.defaultModel]
        )
        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "recent prometheus").flatMap(\.models).map(\.id),
            [TrustedRouterDefaults.prometheusModel]
        )
    }

    func testModelCategorySearchFilterMatchesStateMetadataRows() {
        let categories = [
            ModelCategorySurface(category: "Coding", models: [
                modelOption(
                    id: "acme/default",
                    provider: "acme",
                    displayName: "Default Model",
                    category: "Coding",
                    selectedModelID: "acme/default",
                    badges: ["Default"]
                ),
                modelOption(
                    id: "acme/other",
                    provider: "acme",
                    displayName: "Other Model",
                    category: "Coding"
                )
            ])
        ]

        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "state current").flatMap(\.models).map(\.id),
            ["acme/default"]
        )
    }

    func testModelCategorySearchFilterMatchesCapabilityMetadata() {
        let categories = [
            ModelCategorySurface(category: "Coding", models: [
                modelOption(
                    id: "acme/vision-code",
                    provider: "acme",
                    displayName: "Vision Code",
                    category: "Coding",
                    capabilities: capabilityMetadata()
                )
            ])
        ]

        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "128K image").flatMap(\.models).map(\.id),
            ["acme/vision-code"]
        )
        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "json mode available").flatMap(\.models).map(\.id),
            ["acme/vision-code"]
        )
    }

    func testModelCategorySearchFilterMatchesCompactProviderModelAliases() {
        let categories = [
            ModelCategorySurface(category: "Coding", models: [
                modelOption(
                    id: "deepseek/deepseek-v4-flash",
                    provider: "deepseek",
                    displayName: "DeepSeek V4 Flash",
                    category: "Coding"
                ),
                modelOption(
                    id: "moonshotai/kimi-k2.6",
                    provider: "moonshotai",
                    displayName: "Kimi K2.6",
                    category: "Coding"
                ),
                modelOption(
                    id: TrustedRouterDefaults.minimaxM3Model,
                    provider: "minimax",
                    displayName: "MiniMax M3",
                    category: "minimax"
                )
            ])
        ]

        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "deepseekv4flash").flatMap(\.models).map(\.id),
            ["deepseek/deepseek-v4-flash"]
        )
        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "kimi k26").flatMap(\.models).map(\.id),
            ["moonshotai/kimi-k2.6"]
        )
        XCTAssertEqual(
            ModelCategorySearchFilter.filter(categories, matching: "minimaxm3").flatMap(\.models).map(\.id),
            [TrustedRouterDefaults.minimaxM3Model]
        )
        XCTAssertTrue(ModelCategorySearchFilter.filter(categories, matching: "! @").isEmpty)
    }

    func testModelOptionBuildsTrustedRouterRecommendedMetadata() throws {
        let option = modelOption(
            id: TrustedRouterDefaults.defaultModel,
            provider: TrustedRouterDefaults.trustedRouterProvider,
            displayName: TrustedRouterDefaults.fastModelDisplayName,
            category: "Recommended",
            selectedModelID: TrustedRouterDefaults.defaultModel,
            badges: ["Default", "Recommended"]
        )

        XCTAssertEqual(option.detailTitle, TrustedRouterDefaults.fastModelDisplayName)
        XCTAssertEqual(option.metadataSummary, "Fast everyday agent")
        XCTAssertEqual(
            option.capabilitySummary,
            "\(TrustedRouterDefaults.fastModelDisplayName) is the fast default for everyday coding, shell, and file-editing turns."
        )
        XCTAssertEqual(option.modelInfo.id, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(option.modelInfo.displayName, TrustedRouterDefaults.fastModelDisplayName)
        XCTAssertTrue(option.metadataDetails.contains("Default model"))
        XCTAssertTrue(option.metadataDetails.contains("Recommended by QuillCode"))

        let state = try XCTUnwrap(option.metadataRows.first { $0.label == "State" })
        XCTAssertEqual(state.value, "Current, Default, Recommended")
    }

    func testModelOptionDecodesOlderPayloadWithoutBadges() throws {
        let json = """
        {
          "id": "tr/fusion",
          "provider": "trustedrouter",
          "displayName": "Old model label",
          "category": "Recommended",
          "isSelected": true
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let option = try JSONDecoder().decode(ModelOptionSurface.self, from: data)

        XCTAssertEqual(option.id, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(option.isFavorite, false)
        XCTAssertEqual(option.badges, [])
        XCTAssertEqual(option.detailTitle, TrustedRouterDefaults.prometheusModelDisplayName)
        XCTAssertEqual(option.metadataSummary, "Freedom, OSS, deep research")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Model ID" }?.value, "/prometheus")
        XCTAssertEqual(option.metadataRows.first { $0.label == "State" }?.value, "Current")
        XCTAssertTrue(option.metadataDetails.contains("Current selection"))
    }

    func testModelOptionBuildsCapabilityRowsFromCatalogMetadata() throws {
        let option = modelOption(
            id: "acme/vision-code",
            provider: "acme",
            displayName: "Vision Code",
            category: "Coding",
            capabilities: capabilityMetadata()
        )

        XCTAssertEqual(option.metadataSummary, "Vision coding model")
        XCTAssertEqual(
            option.capabilitySummary,
            "128K context · text, image -> text · $0.25 in / $1.25 out per 1M · tools, json mode · available"
        )
        XCTAssertEqual(option.metadataRows.first { $0.label == "Context" }?.value, "128K")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Modalities" }?.value, "text, image -> text")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Pricing" }?.value, "$0.25 in / $1.25 out per 1M")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Capabilities" }?.value, "tools, json mode")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Status" }?.value, "available")
        XCTAssertTrue(option.metadataDetails.contains("Context: 128K"))
    }

    func testModelOptionPreservesCapabilitiesAcrossJSONRoundTrip() throws {
        let option = modelOption(
            id: "acme/vision-code",
            provider: "acme",
            displayName: "Vision Code",
            category: "Coding",
            capabilities: capabilityMetadata()
        )

        let data = try JSONEncoder().encode(option)
        let decoded = try JSONDecoder().decode(ModelOptionSurface.self, from: data)

        XCTAssertEqual(decoded.capabilities, option.capabilities)
        XCTAssertEqual(decoded.metadataRows, option.metadataRows)
        XCTAssertEqual(decoded.modelInfo.capabilities, option.capabilities)
    }

    func testModelCategoryAndMetadataRowIdentifiersAreStable() {
        let category = ModelCategorySurface(category: "Recommended", models: [])
        let row = ModelMetadataRowSurface(label: "Provider", value: "trustedrouter")

        XCTAssertEqual(category.id, "Recommended")
        XCTAssertEqual(row.id, "Provider")
    }

    func testAgentStatusPresentationClassifiesActionableStatusTones() {
        XCTAssertEqual(TopBarStatusPresentation.agentStatus(TopBarAgentStatusLabel.idle), TopBarStatusPresentation(
            label: TopBarAgentStatusLabel.idle,
            tone: .idle,
            showsIndicator: false
        ))
        XCTAssertEqual(TopBarStatusPresentation.agentStatus(TopBarAgentStatusLabel.running), TopBarStatusPresentation(
            label: TopBarAgentStatusLabel.running,
            tone: .running,
            showsIndicator: true
        ))
        XCTAssertEqual(TopBarStatusPresentation.agentStatus(TopBarAgentStatusLabel.terminal), TopBarStatusPresentation(
            label: TopBarAgentStatusLabel.terminal,
            tone: .running,
            showsIndicator: true
        ))
        XCTAssertEqual(TopBarStatusPresentation.agentStatus(TopBarAgentStatusLabel.failed), TopBarStatusPresentation(
            label: TopBarAgentStatusLabel.failed,
            tone: .failed,
            showsIndicator: true
        ))
        XCTAssertEqual(TopBarStatusPresentation.agentStatus(TopBarAgentStatusLabel.stopped), TopBarStatusPresentation(
            label: TopBarAgentStatusLabel.stopped,
            tone: .stopped,
            showsIndicator: true
        ))
    }

    func testAgentStatusLabelsPreserveStableUserFacingCopy() {
        XCTAssertEqual(TopBarAgentStatusLabel.idle, "Idle")
        XCTAssertEqual(TopBarAgentStatusLabel.queued, "Queued")
        XCTAssertEqual(TopBarAgentStatusLabel.running, "Running")
        XCTAssertEqual(TopBarAgentStatusLabel.review, "Review")
        XCTAssertEqual(TopBarAgentStatusLabel.streaming, "Streaming")
        XCTAssertEqual(TopBarAgentStatusLabel.finishing, "Finishing")
        XCTAssertEqual(TopBarAgentStatusLabel.failed, "Failed")
        XCTAssertEqual(TopBarAgentStatusLabel.stopped, "Stopped")
        XCTAssertEqual(TopBarAgentStatusLabel.terminal, "Terminal")
    }

    func testRuntimeIssuePresentationUsesWarningByDefaultAndErrorWhenExplicit() {
        var topBar = makeTopBar(runtimeIssueLabel: nil, runtimeIssueSeverity: nil)
        XCTAssertNil(topBar.runtimeIssuePresentation)

        topBar = makeTopBar(runtimeIssueLabel: "Rate limited", runtimeIssueSeverity: nil)
        XCTAssertEqual(topBar.runtimeIssuePresentation, TopBarRuntimeIssuePresentation(label: "Rate limited", tone: .warning))

        topBar = makeTopBar(runtimeIssueLabel: "Missing key", runtimeIssueSeverity: .error)
        XCTAssertEqual(topBar.runtimeIssuePresentation, TopBarRuntimeIssuePresentation(label: "Missing key", tone: .error))
    }

    func testTopBarPresentationTextIncludesQuietMetadataOnce() {
        var topBar = makeTopBar(runtimeIssueLabel: "Rate limited", runtimeIssueSeverity: nil)
        topBar.branchStatusLabel = "main ↑2"
        topBar.usageStatusLabel = "42 ctx"

        XCTAssertEqual(
            topBar.topBarHelpText,
            "Ready. Agent status: Running. Issue: Rate limited"
        )
        XCTAssertEqual(
            topBar.topBarAccessibilityLabel,
            "Project, Ready, Agent status: Running, branch: main ↑2, token usage: 42 ctx, issue: Rate limited"
        )
        XCTAssertTrue(topBar.showsActivityHairline)

        topBar.spendStatusLabel = "Spend $0.0050 / $1.00"
        XCTAssertEqual(
            topBar.topBarAccessibilityLabel,
            "Project, Ready, Agent status: Running, branch: main ↑2, spend: Spend $0.0050 / $1.00, issue: Rate limited"
        )
        XCTAssertEqual(
            topBar.topBarHelpText,
            "Ready. Agent status: Running. Issue: Rate limited"
        )

        topBar.tokenBudget = TokenBudgetSurface(
            usedTokens: 42,
            limitTokens: 32_000,
            remainingTokens: 31_958,
            usedPercent: 0,
            progressPercent: 0,
            primaryLabel: "42 / 32k tokens",
            secondaryLabel: "32k left · 0% · estimated",
            detailLabel: "Estimated token budget: 42 used of 32,000 · 31,958 left · 0% used",
            sourceLabel: "Estimated"
        )
        XCTAssertEqual(
            topBar.topBarAccessibilityLabel,
            "Project, Ready, Agent status: Running, branch: main ↑2, token budget: Estimated token budget: 42 used of 32,000 · 31,958 left · 0% used, spend: Spend $0.0050 / $1.00, issue: Rate limited"
        )
        XCTAssertEqual(
            topBar.topBarHelpText,
            "Ready. Agent status: Running. Estimated token budget: 42 used of 32,000 · 31,958 left · 0% used. Issue: Rate limited"
        )
    }

    private func filteredModelIDs(_ topBar: TopBarSurface, query: String) -> [String] {
        topBar.filteredModelCategories(matching: query).flatMap(\.models).map(\.id)
    }

    private func makeTopBar(
        runtimeIssueLabel: String?,
        runtimeIssueSeverity: RuntimeIssueSeverity?
    ) -> TopBarSurface {
        TopBarSurface(
            appName: "QuillCode",
            primaryTitle: "Project",
            subtitle: "Ready",
            instructionLabel: "Instructions",
            instructionSources: [],
            memoryLabel: "Memory",
            memorySources: [],
            modelLabel: TrustedRouterDefaults.fastModelDisplayName,
            selectedModelID: TrustedRouterDefaults.defaultModel,
            modelCategories: [],
            modeLabel: "Auto",
            agentStatus: "Running",
            runtimeIssueLabel: runtimeIssueLabel,
            runtimeIssueSeverity: runtimeIssueSeverity,
            computerUseLabel: "Computer Use Ready",
            showsComputerUseSetup: false
        )
    }

    private func modelOption(
        id: String,
        provider: String,
        displayName: String,
        category: String,
        selectedModelID: String = "other/model",
        isFavorite: Bool = false,
        badges: [String] = [],
        capabilities: ModelCapabilities = .init()
    ) -> ModelOptionSurface {
        ModelOptionSurface(
            model: ModelInfo(
                id: id,
                provider: provider,
                displayName: displayName,
                category: category,
                capabilities: capabilities
            ),
            selectedModelID: selectedModelID,
            isFavorite: isFavorite,
            badges: badges
        )
    }

    private func capabilityMetadata() -> ModelCapabilities {
        ModelCapabilities(
            contextWindowTokens: 128_000,
            inputPricePerMillionTokens: 0.25,
            outputPricePerMillionTokens: 1.25,
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            capabilityTags: ["tools", "json mode"],
            status: "available",
            summary: "Vision coding model"
        )
    }
}
