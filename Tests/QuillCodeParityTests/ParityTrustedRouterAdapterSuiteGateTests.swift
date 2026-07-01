import XCTest

final class ParityTrustedRouterAdapterSuiteGateTests: QuillCodeParityTestCase {
    func testTrustedRouterAdapterCoverageUsesFocusedSuites() throws {
        let testRoot = Self.packageRoot()
            .appendingPathComponent("Tests/QuillCodeAgentTests")
        let oldAdapterTest = testRoot
            .appendingPathComponent("TrustedRouterAdapterTests.swift")

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldAdapterTest.path))

        try assertActionParserSuite()
        try assertStreamingSuite()
        try assertPromptSuite()
        try assertCatalogSuite()
        try assertKeyResolverSuite()
    }

    private func assertActionParserSuite() throws {
        let parser = try Self.agentTestSourceText(
            named: "TrustedRouterActionParserTests.swift"
        )
        let normalizer = try Self.agentTestSourceText(
            named: "AgentToolArgumentNormalizerTests.swift"
        )

        XCTAssertTrue(parser.contains("final class TrustedRouterActionParserTests"))
        XCTAssertTrue(parser.contains("AgentActionJSONParser.parse"))
        XCTAssertTrue(parser.contains("testActionParserNormalizesPullRequestLabelAliases"))
        XCTAssertTrue(normalizer.contains("final class AgentToolArgumentNormalizerTests"))
        XCTAssertTrue(normalizer.contains("testCanonicalArgumentsNormalizePullRequestCollectionAliases"))
        XCTAssertTrue(normalizer.contains("testShellCommandRecoveryRepairsEmptyArguments"))
    }

    private func assertStreamingSuite() throws {
        let text = try Self.agentTestSourceText(
            named: "TrustedRouterStreamingActionTests.swift"
        )

        XCTAssertTrue(text.contains("final class TrustedRouterStreamingActionTests"))
        XCTAssertTrue(text.contains("AgentActionStreamCollector.collect"))
        XCTAssertTrue(text.contains("AgentActionStreamPreview.visibleAssistantText"))
    }

    private func assertPromptSuite() throws {
        let text = try Self.agentTestSourceText(
            named: "TrustedRouterPromptBuilderTests.swift"
        )

        XCTAssertTrue(text.contains("final class TrustedRouterPromptBuilderTests"))
        XCTAssertTrue(text.contains("TrustedRouterPromptBuilder.systemPrompt"))
        XCTAssertTrue(text.contains("testMessagesIncludeMemoriesAsAuditableSystemContext"))
    }

    private func assertCatalogSuite() throws {
        let text = try Self.agentTestSourceText(
            named: "TrustedRouterModelCatalogTests.swift"
        )

        XCTAssertTrue(text.contains("final class TrustedRouterModelCatalogTests"))
        XCTAssertTrue(text.contains("TrustedRouterModelCatalog.defaultModels"))
        XCTAssertTrue(text.contains("testModelCatalogAlwaysIncludesRankedRecommendedFallbacks"))
    }

    private func assertKeyResolverSuite() throws {
        let text = try Self.agentTestSourceText(
            named: "TrustedRouterAPIKeyResolverTests.swift"
        )

        XCTAssertTrue(text.contains("final class TrustedRouterAPIKeyResolverTests"))
        XCTAssertTrue(text.contains("TrustedRouterAPIKeyResolver("))
        XCTAssertTrue(text.contains("StaticTrustedRouterSessionStore"))
    }
}
