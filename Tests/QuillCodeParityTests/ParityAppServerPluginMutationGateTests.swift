import XCTest

final class ParityAppServerPluginMutationGateTests: QuillCodeParityTestCase {
    func testLocalPluginMutationStaysWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let mutation = try text(root, "Sources/QuillCodeCLI/AppServerPluginMutation.swift")
        let store = try text(root, "Sources/QuillCodeTools/CodexInstalledPluginStore.swift")
        let installer = try text(
            root,
            "Sources/QuillCodeTools/BoundedPluginPackageInstaller.swift"
        )
        let tests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerPluginDiscoveryTests.swift"
        )
        let storeTests = try text(
            root,
            "Tests/QuillCodeToolsTests/CodexInstalledPluginStoreTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, containsAll: [
            "case \"plugin/install\"",
            "case \"plugin/uninstall\""
        ])
        Self.assertSource(mutation, containsAll: [
            "func installPlugin",
            "func uninstallPlugin",
            "remote plugin install is not available",
            "pluginMutationDidChangeSkills",
            "skills/changed"
        ])
        Self.assertSource(store, containsAll: [
            "plugins/cache",
            "public func install",
            "public func uninstall",
            "Uninstall is intentionally idempotent"
        ])
        Self.assertSource(installer, containsAll: [
            "maximumFiles",
            "maximumBytes",
            "replaceExisting",
            "unsupportedEntry",
            "replacementRecoveryFailed"
        ])
        Self.assertSource(tests, containsAll: [
            "testPluginInstallActivatesGlobalPackageAndUninstallIsIdempotent",
            "testPluginMutationValidatesPolicySourcesAndPluginIDs"
        ])
        Self.assertSource(storeTests, containsAll: [
            "testInstallReplaceDiscoverSkillsAndIdempotentUninstall",
            "testRejectsInvalidIdentityAndSymbolicPackageEntries"
        ])
        Self.assertSource(smoke, containsAll: [
            "\"method\": \"plugin/install\"",
            "\"method\": \"plugin/uninstall\"",
            "smoke-plugin-skill"
        ])
        Self.assertSource(parity, contains: "local `plugin/install` and `plugin/uninstall`")
        Self.assertSource(research, contains: "plugin/install")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
