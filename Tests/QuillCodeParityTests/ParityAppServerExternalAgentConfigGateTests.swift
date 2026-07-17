import XCTest

final class ParityAppServerExternalAgentConfigGateTests: QuillCodeParityTestCase {
    func testExternalAgentConfigMigrationStaysWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let lifecycle = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionExternalAgentConfig.swift"
        )
        let service = try text(
            root,
            "Sources/QuillCodePersistence/ClaudeCodeExternalAgentConfigService.swift"
        )
        let tests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerExternalAgentConfigTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")
        let testPlan = try Self.docsText(named: "TEST_PLAN.md")

        Self.assertSource(session, containsAll: [
            "case \"externalAgentConfig/detect\"",
            "case \"externalAgentConfig/import/readHistories\"",
            "case \"externalAgentConfig/import\"",
            "launchExternalAgentConfigImport"
        ])
        Self.assertSource(lifecycle, containsAll: [
            "externalAgentConfig/import/progress",
            "externalAgentConfig/import/completed",
            "groupedImportResults",
            "persistExternalAgentSession",
            "cancelAllExternalAgentConfigImports"
        ])
        Self.assertSource(service, containsAll: [
            "acquireImportPermit",
            "migration_item_not_detected",
            "resolvingSymlinksInPath",
            "historyStore.record"
        ])
        Self.assertSource(tests, containsAll: [
            "testDetectDefaultsEmptyAndScopesHomeAndRepository",
            "testImportRespondsBeforeProgressContinuesAfterFailureAndPersistsHistory",
            "testSessionImportCreatesDurableProjectThreadAndSuppressesRedetection",
            "testEndOfInputCancelsImportBeforeProgressOrCompletion"
        ])
        Self.assertSource(smoke, containsAll: [
            "externalAgentConfig/detect",
            "externalAgentConfig/import",
            "externalAgentConfig/import/progress",
            "externalAgentConfig/import/completed",
            "externalAgentConfig/import/readHistories"
        ])
        Self.assertSource(parity, contains: "App-server external-agent migration")
        Self.assertSource(
            decisions,
            contains: "App-server agent migration revalidates and serializes every item"
        )
        Self.assertSource(research, contains: "externalAgentConfig/import/readHistories")
        Self.assertSource(testPlan, contains: "App-server external-agent migration conformance")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
