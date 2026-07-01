import XCTest

final class ParityWorkspaceConfigurationGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesConfigurationTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let extensionText = try Self.appSourceText(named: "WorkspaceModelConfiguration.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceConfigurationEngine.swift")

        assertConfigurationEngineContracts(engineText)
        assertConfigurationExtensionAPI(extensionText)
        assertConfigurationExtensionDelegates(extensionText)
        assertWorkspaceModelAvoidsConfigurationOwnership(modelText)
    }

    func testWorkspaceConfigurationIntegrationTestsOwnModelConfigurationFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let integrationTests = try Self.appTestSourceText(
            named: "WorkspaceConfigurationIntegrationTests.swift"
        )

        [
            "testModeAndModelUpdateSelectedThreadAndTopBar",
            "testToggleModelFavoriteUpdatesConfigAndSurface",
            "testApplySettingsUpdatesConfigThreadAndSettingsSurface",
            "testBootstrapLoadsConfigAndPersistedThreads",
            "testBootstrapPersistsAndClearsTrustedRouterAPIKey"
        ].forEach {
            Self.assertSource(integrationTests, contains: $0)
            Self.assertSource(modelTests, excludes: $0)
        }
    }

    private func assertConfigurationEngineContracts(_ source: String) {
        [
            "struct WorkspaceConfigurationEngine",
            "static func setModel",
            "static func setMode",
            "static func toggleFavorite",
            "static func normalizedCatalog",
            "static func applySettings",
            "static func syncThread"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertConfigurationExtensionAPI(_ source: String) {
        [
            "public func setMode",
            "public func setModel",
            "public func toggleModelFavorite",
            "public func setModelCatalog",
            "public func applySettings",
            "public func applyRuntime",
            "public func setAgentStatus"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertConfigurationExtensionDelegates(_ source: String) {
        [
            "WorkspaceConfigurationEngine.setModel",
            "WorkspaceConfigurationEngine.setMode",
            "WorkspaceConfigurationEngine.toggleFavorite",
            "WorkspaceConfigurationEngine.normalizedCatalog",
            "WorkspaceConfigurationEngine.applySettings"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertWorkspaceModelAvoidsConfigurationOwnership(_ modelText: String) {
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
}
