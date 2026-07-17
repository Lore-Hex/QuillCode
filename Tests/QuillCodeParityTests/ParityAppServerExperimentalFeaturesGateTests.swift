import XCTest

final class ParityAppServerExperimentalFeaturesGateTests: QuillCodeParityTestCase {
    func testExperimentalFeaturesStayWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let catalog = try text(root, "Sources/QuillCodeCore/QuillCodeFeatureCatalog.swift")
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let features = try text(root, "Sources/QuillCodeCLI/AppServerExperimentalFeatures.swift")
        let runtimeStore = try text(
            root,
            "Sources/QuillCodeCLI/AppServerRuntimeFeatureStore.swift"
        )
        let webSocket = try text(root, "Sources/QuillCodeCLI/AppServerWebSocketTransport.swift")
        let unixSocket = try text(root, "Sources/QuillCodeCLI/AppServerUnixSocketTransport.swift")
        let turns = try text(root, "Sources/QuillCodeCLI/AppServerSessionTurns.swift")
        let parser = try text(root, "Sources/QuillCodeCLI/CLIArgumentParser.swift")
        let featureTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerExperimentalFeatureTests.swift"
        )
        let memoryTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerThreadControlTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")

        Self.assertSource(catalog, containsAll: [
            "QuillCodeFeatureCatalog",
            "supportsRuntimeEnablement",
            "case memories",
            "case hooks"
        ])
        Self.assertSource(session, containsAll: [
            "case \"experimentalFeature/list\"",
            "case \"experimentalFeature/enablement/set\"",
            "runtimeFeatureStore"
        ])
        Self.assertSource(features, containsAll: [
            "func listExperimentalFeatures",
            "func setExperimentalFeatureEnablement",
            "requirements?.featureRequirements",
            "request.featureEnablement",
            "configuredFeatureEnablement",
            "runtimeFeatureStore.value",
            "defaultEnabled"
        ])
        Self.assertSource(runtimeStore, containsAll: [
            "actor AppServerRuntimeFeatureStore",
            "func value(for featureName:",
            "func merge(_ updates:"
        ])
        Self.assertSource(webSocket, contains: "runtimeFeatureStore: runtimeFeatureStore")
        Self.assertSource(unixSocket, contains: "runtimeFeatureStore: runtimeFeatureStore")
        Self.assertSource(turns, containsAll: [
            "experimentalFeatureEnabled(",
            ".memories,",
            "modelThread.memories = []",
            "result.thread.memories = durableMemories"
        ])
        Self.assertSource(parser, containsAll: ["--enable", "--disable", "unknownFeatureFlag"])
        Self.assertSource(featureTests, containsAll: [
            "testListProjectsMetadataAndCodexPagination",
            "testRuntimePatchFiltersKeysAndRespectsConfigPrecedence",
            "testRuntimePatchIsSharedAcrossSessions",
            "testResolutionUsesThreadProjectCLIAndManagedPrecedence",
            "testListRefreshesLoadedThreadProjectConfig"
        ])
        Self.assertSource(memoryTests, contains: "testRuntimeMemoryFeatureChangesModelContextWithoutDeletingNotes")
        Self.assertSource(smoke, containsAll: [
            "experimentalFeature/list",
            "experimentalFeature/enablement/set"
        ])
        Self.assertSource(parity, contains: "App-server experimental feature catalog")
        Self.assertSource(research, contains: "experimental feature discovery")
        Self.assertSource(decisions, contains: "Experimental feature state uses one real precedence chain")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
