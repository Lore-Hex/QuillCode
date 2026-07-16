import XCTest

final class ParityAppServerHooksListGateTests: QuillCodeParityTestCase {
    func testHooksListStaysWiredThroughSharedDiscoveryTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let endpoint = try text(root, "Sources/QuillCodeCLI/AppServerHooksList.swift")
        let catalog = try text(root, "Sources/QuillCodeHooks/HookCatalog.swift")
        let projectLoader = try text(
            root,
            "Sources/QuillCodeHooks/ProjectHookConfigurationLoader.swift"
        )
        let pluginLoader = try text(
            root,
            "Sources/QuillCodeHooks/CodexPluginHookConfigurationLoader.swift"
        )
        let rootResolver = try text(
            root,
            "Sources/QuillCodeTools/GitRepositoryRootResolver.swift"
        )
        let protocolTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerDiscoveryTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, contains: "case \"hooks/list\"")
        Self.assertSource(endpoint, containsAll: [
            "func listHooks",
            "GlobalHookConfigurationLoader.load",
            "ProjectHookConfigurationLoader.discover",
            "CodexPluginHookConfigurationLoader.discover",
            "GitRepositoryRootResolver.resolve",
            "HookCatalogResolver.resolve",
            "\"currentHash\"",
            "\"trustStatus\""
        ])
        Self.assertSource(catalog, containsAll: [
            "public enum HookCatalogSource",
            "public enum HookCatalogTrustStatus",
            "public enum HookCatalogResolver"
        ])
        Self.assertSource(projectLoader, containsAll: [
            "HookConfigurationDiagnostic",
            "hookStates",
            "hooksFeatureOverride"
        ])
        Self.assertSource(pluginLoader, containsAll: [
            "path, path array, hook object, or hook object array",
            "resolvingSymlinksInPath",
            "maximumHookFileBytes"
        ])
        Self.assertSource(rootResolver, containsAll: [
            "Linked worktrees read project configuration from their primary checkout",
            "commondir",
            "maxMarkerBytes"
        ])
        Self.assertSource(protocolTests, containsAll: [
            "testHooksListDefaultsToSessionCWDAndReturnsExactDataOnlyShape",
            "testHooksListReflectsBatchWrittenEnabledAndTrustState",
            "testHooksListUsesPrimaryCheckoutForLinkedWorktreeAndProjectFeatureOverride",
            "testHooksListReturnsPluginWarningsAndPerCWDLoadErrors"
        ])
        Self.assertSource(smoke, containsAll: [
            "\"method\": \"hooks/list\"",
            "hooks-list-must-not-execute"
        ])
        Self.assertSource(parity, contains: "App-server hook discovery")
        Self.assertSource(research, contains: "hooks/list")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
