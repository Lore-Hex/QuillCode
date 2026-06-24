import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeTopBarSurfaceTests: XCTestCase {
    func testTopBarFiltersModelCategoriesByMetadataFavoritesAndRecents() {
        let topBar = TopBarSurface(
            appName: "QuillCode",
            primaryTitle: "Project",
            subtitle: "Ready",
            instructionLabel: "Instructions",
            instructionSources: [],
            memoryLabel: "Memory",
            memorySources: [],
            modelLabel: TrustedRouterDefaults.synthModelDisplayName,
            selectedModelID: TrustedRouterDefaults.synthModel,
            modelCategories: [
                ModelCategorySurface(category: "Favorites", models: [
                    modelOption(
                        id: TrustedRouterDefaults.synthModel,
                        provider: TrustedRouterDefaults.trustedRouterProvider,
                        displayName: TrustedRouterDefaults.synthModelDisplayName,
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
        XCTAssertEqual(filteredModelIDs(topBar, query: "favorite synth"), [TrustedRouterDefaults.synthModel])
        XCTAssertEqual(filteredModelIDs(topBar, query: "recent moon k2"), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(filteredModelIDs(topBar, query: "coding"), ["acme/code-pro"])
        XCTAssertTrue(topBar.filteredModelCategories(matching: "does-not-exist").isEmpty)
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
                    id: TrustedRouterDefaults.synthModel,
                    provider: TrustedRouterDefaults.trustedRouterProvider,
                    displayName: TrustedRouterDefaults.synthModelDisplayName,
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
            [TrustedRouterDefaults.synthModel]
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
            "\(TrustedRouterDefaults.fastModelDisplayName) is the fast default for coding, shell, and file-editing turns."
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

        XCTAssertEqual(option.id, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(option.isFavorite, false)
        XCTAssertEqual(option.badges, [])
        XCTAssertEqual(option.detailTitle, TrustedRouterDefaults.synthModelDisplayName)
        XCTAssertEqual(option.metadataSummary, "Deeper planning and review")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Model ID" }?.value, "/synth")
        XCTAssertEqual(option.metadataRows.first { $0.label == "State" }?.value, "Current")
        XCTAssertTrue(option.metadataDetails.contains("Current selection"))
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
        badges: [String] = []
    ) -> ModelOptionSurface {
        ModelOptionSurface(
            model: ModelInfo(
                id: id,
                provider: provider,
                displayName: displayName,
                category: category
            ),
            selectedModelID: selectedModelID,
            isFavorite: isFavorite,
            badges: badges
        )
    }
}
