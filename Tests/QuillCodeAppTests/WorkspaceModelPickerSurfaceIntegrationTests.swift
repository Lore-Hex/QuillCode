import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceModelPickerSurfaceIntegrationTests: XCTestCase {
    func testSurfaceGroupsCustomModelCatalogByCategory() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "acme/code-pro"),
            topBar: TopBarState(model: "acme/code-pro")
        ))
        model.setModelCatalog([
            .init(id: TrustedRouterDefaults.synthModel, provider: "trustedrouter", displayName: TrustedRouterDefaults.synthModelDisplayName, category: "Recommended"),
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "acme/fast", provider: "acme", displayName: "Fast", category: "Coding")
        ])

        let surface = model.surface()

        XCTAssertEqual(surface.topBar.modelLabel, "acme/Code Pro")
        XCTAssertEqual(surface.topBar.modelCategories.map(\.category), ["Recommended", "Safety", "Coding"])
        let recommended = surface.topBar.modelCategories.first { $0.category == "Recommended" }
        XCTAssertEqual(recommended?.models.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
        let coding = surface.topBar.modelCategories.first { $0.category == "Coding" }
        XCTAssertEqual(coding?.models.map(\.id), ["acme/code-pro", "acme/fast"])
        XCTAssertTrue(coding?.models.first?.isSelected == true)
    }

    func testTopBarFiltersModelCatalogByProviderCategoryAndModel() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: TrustedRouterDefaults.synthModel),
            topBar: TopBarState(model: TrustedRouterDefaults.synthModel)
        ))
        model.setModelCatalog([
            .init(id: TrustedRouterDefaults.synthModel, provider: "trustedrouter", displayName: TrustedRouterDefaults.synthModelDisplayName, category: "Recommended"),
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "moonshotai/kimi-k2.6", provider: "moonshotai", displayName: "Kimi K2.6", category: "Safety")
        ])

        let topBar = model.surface().topBar

        XCTAssertEqual(topBar.filteredModelCategories(matching: "coding").flatMap(\.models).map(\.id), ["acme/code-pro"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "moon k2").flatMap(\.models).map(\.id), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(
            topBar.filteredModelCategories(matching: "synth").flatMap(\.models).map(\.id),
            [TrustedRouterDefaults.synthModel, TrustedRouterDefaults.synthCodeModel]
        )
        XCTAssertEqual(
            topBar.filteredModelCategories(matching: "tr/synth-code").flatMap(\.models).map(\.id),
            [TrustedRouterDefaults.synthCodeModel]
        )
        XCTAssertEqual(topBar.filteredModelCategories(matching: "default model").flatMap(\.models).map(\.id), [TrustedRouterDefaults.synthModel])
        XCTAssertTrue(topBar.filteredModelCategories(matching: "does-not-exist").isEmpty)
    }

    func testTopBarSurfacesLiveModelCapabilityMetadata() throws {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "acme/vision-code"),
            topBar: TopBarState(model: "acme/vision-code")
        ))
        model.setModelCatalog([
            .init(
                id: "acme/vision-code",
                provider: "acme",
                displayName: "Vision Code",
                category: "Coding",
                capabilities: ModelCapabilities(
                    contextWindowTokens: 128_000,
                    inputPricePerMillionTokens: 0.25,
                    outputPricePerMillionTokens: 1.25,
                    inputModalities: ["text", "image"],
                    outputModalities: ["text"],
                    capabilityTags: ["tools", "json mode"],
                    status: "available",
                    summary: "Vision coding model"
                )
            )
        ])

        let topBar = model.surface().topBar
        let option = try XCTUnwrap(topBar.modelCategories.flatMap(\.models).first { $0.id == "acme/vision-code" })

        XCTAssertEqual(option.metadataSummary, "Vision coding model")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Context" }?.value, "128K")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Pricing" }?.value, "$0.25 in / $1.25 out per 1M")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Modalities" }?.value, "text, image -> text")
        XCTAssertEqual(option.metadataRows.first { $0.label == "Capabilities" }?.value, "tools, json mode")
        XCTAssertEqual(topBar.filteredModelCategories(matching: "128K image").flatMap(\.models).map(\.id), ["acme/vision-code"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "json mode available").flatMap(\.models).map(\.id), ["acme/vision-code"])
    }

    func testSurfaceKeepsUnknownSelectedModelVisible() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "custom/edge-model"),
            topBar: TopBarState(model: "custom/edge-model"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let surface = model.surface()
        let current = surface.topBar.modelCategories.first { $0.category == "Current" }

        XCTAssertEqual(surface.topBar.modelLabel, "custom/edge-model")
        XCTAssertEqual(current?.models.first?.id, "custom/edge-model")
        XCTAssertEqual(current?.models.first?.displayName, "Edge Model")
        XCTAssertTrue(current?.models.first?.isSelected == true)
    }

    func testModelPickerShowsRecentModelsAndBadges() throws {
        let older = ChatThread(
            title: "Older model",
            model: "z-ai/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ChatThread(
            title: "Newer model",
            model: "moonshotai/kimi-k2.6",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: TrustedRouterDefaults.defaultModel),
            threads: [older, newer],
            selectedThreadID: newer.id,
            topBar: TopBarState(model: "moonshotai/kimi-k2.6"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let topBar = model.surface().topBar
        let recent = try XCTUnwrap(topBar.modelCategories.first)

        XCTAssertEqual(recent.category, "Recent")
        XCTAssertEqual(recent.models.map(\.id), ["moonshotai/kimi-k2.6", "z-ai/glm-5.2"])
        XCTAssertEqual(recent.models.first?.badges, ["Recent", "Current"])

        let defaultOption = try XCTUnwrap(topBar.modelCategories
            .flatMap(\.models)
            .first { $0.id == TrustedRouterDefaults.defaultModel })
        XCTAssertTrue(defaultOption.badges.contains("Default"))
        XCTAssertTrue(defaultOption.badges.contains("Recommended"))
        XCTAssertEqual(defaultOption.metadataSummary, "Fast everyday agent")
        XCTAssertEqual(defaultOption.detailTitle, "Nike 1.0")
        XCTAssertEqual(defaultOption.capabilitySummary, "Nike 1.0 is the fast default for coding, shell, and file-editing turns.")
        XCTAssertTrue(defaultOption.metadataDetails.contains("Provider: trustedrouter"))
        XCTAssertTrue(defaultOption.metadataDetails.contains("Model ID: trustedrouter/fast"))
        XCTAssertTrue(defaultOption.metadataDetails.contains("Category: Recommended"))
        XCTAssertEqual(defaultOption.metadataRows.map(\.label), ["Provider", "Model ID", "Category", "State"])
        XCTAssertEqual(defaultOption.metadataRows.first { $0.label == "State" }?.value, "Default, Recommended")

        XCTAssertEqual(topBar.filteredModelCategories(matching: "moon k2").flatMap(\.models).map(\.id), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "recent").first?.category, "Recent")
        XCTAssertEqual(topBar.filteredModelCategories(matching: "nike default").flatMap(\.models).map(\.id), [TrustedRouterDefaults.defaultModel])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "default state").flatMap(\.models).map(\.id), [TrustedRouterDefaults.defaultModel])
    }

    func testModelPickerShowsFavoriteModelsBeforeRecent() throws {
        let older = ChatThread(
            title: "Favorite model",
            model: "z-ai/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ChatThread(
            title: "Recent model",
            model: "moonshotai/kimi-k2.6",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(
                defaultModel: TrustedRouterDefaults.synthModel,
                favoriteModels: [" z-ai/glm-5.2 ", "z-ai/glm-5.2"]
            ),
            threads: [older, newer],
            selectedThreadID: newer.id,
            topBar: TopBarState(model: "moonshotai/kimi-k2.6"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let topBar = model.surface().topBar
        XCTAssertEqual(topBar.modelCategories.prefix(2).map(\.category), ["Favorites", "Recent"])

        let favorite = try XCTUnwrap(topBar.modelCategories.first)
        XCTAssertEqual(favorite.models.map(\.id), ["z-ai/glm-5.2"])
        XCTAssertTrue(favorite.models.first?.isFavorite == true)
        XCTAssertEqual(favorite.models.first?.badges, ["Favorite"])

        let recent = try XCTUnwrap(topBar.modelCategories.dropFirst().first)
        XCTAssertEqual(recent.models.map(\.id), ["moonshotai/kimi-k2.6"])

        XCTAssertEqual(topBar.filteredModelCategories(matching: "favorite").map(\.category), ["Favorites"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "glm").flatMap(\.models).map(\.id), ["z-ai/glm-5.2"])
    }
}
