import XCTest

final class ParityWorkspaceConfigurationGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesConfigurationTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let configurationExtensionText = try Self.appSourceText(named: "WorkspaceModelConfiguration.swift")
        let configurationText = try Self.appSourceText(named: "WorkspaceConfigurationEngine.swift")

        [
            "struct WorkspaceConfigurationEngine",
            "static func setModel",
            "static func setMode",
            "static func toggleFavorite",
            "static func normalizedCatalog",
            "static func applySettings",
            "static func syncThread"
        ].forEach { Self.assertSource(configurationText, contains: $0) }
        [
            "public func setMode",
            "public func setModel",
            "public func toggleModelFavorite",
            "public func setModelCatalog",
            "public func applySettings",
            "public func applyRuntime",
            "public func setAgentStatus",
            "WorkspaceConfigurationEngine.setModel",
            "WorkspaceConfigurationEngine.setMode",
            "WorkspaceConfigurationEngine.toggleFavorite",
            "WorkspaceConfigurationEngine.normalizedCatalog",
            "WorkspaceConfigurationEngine.applySettings"
        ].forEach { Self.assertSource(configurationExtensionText, contains: $0) }
        [
            "public func setMode",
            "public func setModel",
            "public func toggleModelFavorite",
            "public func setModelCatalog",
            "public func applySettings",
            "public func applyRuntime",
            "public func setAgentStatus",
            "TrustedRouterDefaults.normalizedDefaultModelID(model)",
            "root.config.favoriteModels.append",
            "TrustedRouterDefaults.normalizedModelCatalog(models)",
            "root.trustedRouterAPIKeyConfigured = trustedRouterAPIKeyConfigured"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }

    func testWorkspaceConfigurationIntegrationTestsOwnModelConfigurationFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let configurationTests = try Self.appTestSourceText(named: "WorkspaceConfigurationIntegrationTests.swift")

        [
            "testModeAndModelUpdateSelectedThreadAndTopBar",
            "testToggleModelFavoriteUpdatesConfigAndSurface",
            "testApplySettingsUpdatesConfigThreadAndSettingsSurface",
            "testBootstrapLoadsConfigAndPersistedThreads",
            "testBootstrapPersistsAndClearsTrustedRouterAPIKey"
        ].forEach {
            Self.assertSource(configurationTests, contains: $0)
            Self.assertSource(modelTests, excludes: $0)
        }
    }
}
