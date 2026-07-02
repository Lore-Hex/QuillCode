import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceConfigurationEngineTests: XCTestCase {
    func testModeUpdatesConfigAndThread() {
        var config = AppConfig(mode: .auto)
        var thread = ChatThread(mode: .auto)

        WorkspaceConfigurationEngine.setMode(.review, config: &config)
        WorkspaceConfigurationEngine.setMode(.review, thread: &thread)

        XCTAssertEqual(config.mode, .review)
        XCTAssertEqual(thread.mode, .review)
    }

    func testModelUpdatesNormalizeAliasesForConfigAndThread() {
        var config = AppConfig(defaultModel: TrustedRouterDefaults.fastModel)
        var thread = ChatThread(model: TrustedRouterDefaults.fastModel)

        let modelID = WorkspaceConfigurationEngine.setModel(" /synth ", config: &config)
        WorkspaceConfigurationEngine.setModelID(modelID, thread: &thread)

        XCTAssertEqual(modelID, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(thread.model, TrustedRouterDefaults.synthModel)
    }

    func testModelUpdatesNormalizeBrandedDefaultName() {
        var config = AppConfig(defaultModel: TrustedRouterDefaults.synthModel)
        var thread = ChatThread(model: TrustedRouterDefaults.synthModel)

        let modelID = WorkspaceConfigurationEngine.setModel(" Nike 1.0 ", config: &config)
        WorkspaceConfigurationEngine.setModelID(modelID, thread: &thread)

        XCTAssertEqual(modelID, TrustedRouterDefaults.fastModel)
        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.fastModel)
        XCTAssertEqual(thread.model, TrustedRouterDefaults.fastModel)
    }

    func testBlankModelFallsBackToDefault() {
        var config = AppConfig(defaultModel: TrustedRouterDefaults.synthModel)
        var thread = ChatThread(model: TrustedRouterDefaults.synthModel)

        let modelID = WorkspaceConfigurationEngine.setModel("   ", config: &config)
        WorkspaceConfigurationEngine.setModelID(modelID, thread: &thread)

        XCTAssertEqual(modelID, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(thread.model, TrustedRouterDefaults.defaultModel)
    }

    func testFavoriteToggleCanonicalizesDedupesAndRejectsBlank() {
        var config = AppConfig(favoriteModels: ["/synth", "z-ai/glm-5.2"])

        XCTAssertFalse(WorkspaceConfigurationEngine.toggleFavorite("  ", config: &config))
        XCTAssertEqual(config.favoriteModels, [TrustedRouterDefaults.synthModel, "z-ai/glm-5.2"])

        XCTAssertTrue(WorkspaceConfigurationEngine.toggleFavorite(" tr/fast ", config: &config))
        XCTAssertEqual(config.favoriteModels, [
            TrustedRouterDefaults.synthModel,
            "z-ai/glm-5.2",
            TrustedRouterDefaults.fastModel
        ])

        XCTAssertTrue(WorkspaceConfigurationEngine.toggleFavorite("/synth", config: &config))
        XCTAssertEqual(config.favoriteModels, [
            "z-ai/glm-5.2",
            TrustedRouterDefaults.fastModel
        ])
    }

    func testCatalogNormalizationRejectsEmptyInputAndKeepsBundledModels() {
        XCTAssertNil(WorkspaceConfigurationEngine.normalizedCatalog(from: []))

        let catalog = WorkspaceConfigurationEngine.normalizedCatalog(from: [
            ModelInfo(id: " /synth ", provider: "tr", displayName: "", category: ""),
            ModelInfo(id: " /synth-code ", provider: "tr", displayName: "Synth Code", category: ""),
            ModelInfo(id: "vendor/model", provider: "vendor", displayName: "Model", category: "Vendor")
        ])

        XCTAssertEqual(catalog?.first?.id, TrustedRouterDefaults.socratesModel)
        XCTAssertTrue(catalog?.contains { $0.id == TrustedRouterDefaults.synthModel && $0.displayName == "Synth" } == true)
        XCTAssertTrue(catalog?.contains { $0.id == TrustedRouterDefaults.synthCodeModel && $0.displayName == "Synth Code" } == true)
        XCTAssertTrue(catalog?.contains { $0.id == "vendor/model" } == true)
    }

    func testApplySettingsUpdatesRootAndSyncsThread() throws {
        let thread = ChatThread(mode: .auto, model: TrustedRouterDefaults.fastModel)
        var root = QuillCodeRootState(threads: [thread], selectedThreadID: thread.id)
        let config = AppConfig(
            defaultModel: "/synth",
            mode: .readOnly,
            apiBaseURL: "https://api.trustedrouter.test/v1",
            developerOverrideEnabled: true,
            computerUseApprovedBundleIdentifiers: ["com.apple.Terminal"],
            computerUseApprovedAppNames: ["Terminal"]
        )

        WorkspaceConfigurationEngine.applySettings(
            config,
            trustedRouterAPIKeyConfigured: true,
            root: &root
        )
        let selectedIndex = try XCTUnwrap(root.threads.firstIndex { $0.id == thread.id })
        WorkspaceConfigurationEngine.syncThread(&root.threads[selectedIndex], to: root.config)

        XCTAssertEqual(root.config, config)
        XCTAssertEqual(root.config.computerUseApprovedBundleIdentifiers, ["com.apple.Terminal"])
        XCTAssertEqual(root.config.computerUseApprovedAppNames, ["Terminal"])
        XCTAssertTrue(root.trustedRouterAPIKeyConfigured)
        XCTAssertEqual(root.threads[selectedIndex].mode, .readOnly)
        XCTAssertEqual(root.threads[selectedIndex].model, TrustedRouterDefaults.synthModel)
    }
}
