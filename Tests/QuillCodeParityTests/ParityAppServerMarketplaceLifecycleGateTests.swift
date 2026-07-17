import XCTest

final class ParityAppServerMarketplaceLifecycleGateTests: QuillCodeParityTestCase {
    func testMarketplaceLifecycleStaysWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let lifecycle = try text(
            root,
            "Sources/QuillCodeCLI/AppServerMarketplaceLifecycle.swift"
        )
        let materializer = try text(
            root,
            "Sources/QuillCodeTools/CodexMarketplaceMaterializer.swift"
        )
        let registry = try text(
            root,
            "Sources/QuillCodePersistence/MarketplaceRegistryStore.swift"
        )
        let tests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerMarketplaceLifecycleTests.swift"
        )
        let aggregateSmoke = try text(root, "scripts/app-server-smoke.sh")
        let smoke = try text(root, "scripts/app-server-marketplace-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, containsAll: [
            "case \"marketplace/add\"",
            "case \"marketplace/remove\"",
            "case \"marketplace/upgrade\""
        ])
        Self.assertSource(lifecycle, containsAll: [
            "func addMarketplace",
            "func removeMarketplace",
            "func upgradeMarketplaces",
            "validateInstalledMarketplace",
            "marketplaceCatalogDidChange",
            "skills/changed"
        ])
        Self.assertSource(materializer, containsAll: [
            "GIT_TERMINAL_PROMPT",
            "maximumEntries",
            "maximumBytes",
            "sparse-checkout",
            "func rollback",
            "validateInstalledMarketplace"
        ])
        Self.assertSource(registry, containsAll: [
            "[marketplaces]",
            "maximumMarketplaces",
            "ConfigDocumentStore",
            "func upsert",
            "func remove"
        ])
        Self.assertSource(tests, containsAll: [
            "testLocalMarketplaceAddIsIdempotentDiscoverableAndRemovable",
            "testGitMarketplaceAddUpgradeAndRemoveAreTransactional",
            "testIdempotentGitAddRejectsDamagedInstalledCatalog",
            "testMarketplaceAddRejectsCatalogRenameAtConfiguredSource",
            "testMarketplaceAddRejectsCredentialsAndUnsafeSparsePaths"
        ])
        Self.assertSource(smoke, containsAll: [
            "\"method\": \"marketplace/add\"",
            "\"method\": \"marketplace/upgrade\"",
            "\"method\": \"marketplace/remove\"",
            "smoke-marketplace"
        ])
        Self.assertSource(
            aggregateSmoke,
            contains: "scripts/app-server-marketplace-smoke.sh"
        )
        Self.assertSource(parity, contains: "`marketplace/add`, `marketplace/remove`, and `marketplace/upgrade`")
        Self.assertSource(research, contains: "marketplace/add")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
