import XCTest

final class ParityAppServerThreadInjectionGateTests: QuillCodeParityTestCase {
    func testThreadInjectionStaysWiredThroughModelHistoryRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let injection = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionThreadInjection.swift"
        )
        let validator = try text(
            root,
            "Sources/QuillCodeCLI/AppServerResponseItemValidator.swift"
        )
        let thread = try text(root, "Sources/QuillCodeCore/ChatThread.swift")
        let prompt = try text(root, "Sources/QuillCodeAgent/TrustedRouterPromptBuilder.swift")
        let protocolTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerThreadInjectionTests.swift"
        )
        let promptTests = try text(
            root,
            "Tests/QuillCodeAgentTests/TrustedRouterPromptBuilderTests.swift"
        )
        let persistenceTests = try text(
            root,
            "Tests/QuillCodePersistenceTests/JSONThreadStoreTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")
        let testPlan = try Self.docsText(named: "TEST_PLAN.md")

        Self.assertSource(session, contains: "case \"thread/inject_items\"")
        Self.assertSource(injection, containsAll: [
            "func injectThreadItems",
            "modelContextItems.append",
            "applyInjectedThread"
        ])
        Self.assertSource(validator, containsAll: [
            "items[\\(index)] is not a valid response item",
            "remote image URLs are not supported",
            "validateResponseItem"
        ])
        Self.assertSource(thread, contains: "modelContextItems")
        Self.assertSource(prompt, containsAll: [
            "orderedModelHistory",
            "ThreadModelContextPromptProjector"
        ])
        Self.assertSource(protocolTests, containsAll: [
            "testInjectedItemsPersistAsModelOnlyHistoryAndStayOutOfThreadProjection",
            "testInjectionValidationMatchesCodexRequestErrors",
            "testInjectionDuringActiveTurnSurvivesCompletionAndReachesNextModelRequest"
        ])
        Self.assertSource(promptTests, containsAll: [
            "testInjectedContextBeforeFirstTurnPrecedesCurrentPrompt",
            "testInjectedContextReplaysImmediatelyAfterItsAnchor",
            "testInjectedContextParticipatesInHistoryLimitAndCacheStability"
        ])
        Self.assertSource(
            persistenceTests,
            contains: "testThreadStoreRoundTripsModelOnlyContextWithoutCreatingMessages"
        )
        Self.assertSource(smoke, containsAll: ["thread/inject_items", "injected-model-only-smoke"])
        Self.assertSource(parity, contains: "App-server model-only context injection")
        Self.assertSource(decisions, contains: "Injected response items use a durable model-only timeline")
        Self.assertSource(research, containsAll: ["thread/inject_items", "model-only"])
        Self.assertSource(testPlan, contains: "App-server model-only context injection")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
