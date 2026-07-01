import XCTest

final class ParityTrustedRouterActionParsingGateTests: QuillCodeParityTestCase {
    func testTrustedRouterActionParsingLivesOutsideTransportClient() throws {
        let client = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let parser = try Self.agentSourceText(named: "AgentActionJSONParser.swift")
        let extractor = try Self.agentSourceText(named: "AgentActionJSONExtractor.swift")
        let recovery = try Self.agentSourceText(named: "AgentShellCommandRecovery.swift")
        let normalizer = try Self.agentSourceText(named: "AgentToolArgumentNormalizer.swift")
        let rules = try Self.agentSourceText(named: "AgentToolArgumentNormalizationRule.swift")

        XCTAssertTrue(parser.contains("public enum AgentActionJSONParser"))
        XCTAssertTrue(extractor.contains("enum AgentActionJSONExtractor"))
        XCTAssertTrue(recovery.contains("enum AgentShellCommandRecovery"))
        XCTAssertTrue(normalizer.contains("enum AgentToolArgumentNormalizer"))
        XCTAssertTrue(rules.contains("enum AgentToolArgumentNormalizationRules"))

        XCTAssertTrue(parser.contains("AgentActionJSONExtractor.actionObject"))
        XCTAssertTrue(parser.contains("AgentToolArgumentNormalizer.canonicalArguments"))
        XCTAssertTrue(normalizer.contains("AgentToolArgumentNormalizationRules.matching"))
        XCTAssertTrue(normalizer.contains("AgentShellCommandRecovery.explicitCommand"))
        XCTAssertTrue(normalizer.contains("canonicalArguments"))
        XCTAssertTrue(client.contains("AgentActionStreamCollector.collect"))

        XCTAssertFalse(client.contains("public enum AgentActionJSONParser"))
        XCTAssertFalse(client.contains("canonicalArguments"))
        XCTAssertFalse(client.contains("AgentShellCommandRecovery"))
        XCTAssertFalse(client.contains("jsonObjectCandidates"))
        XCTAssertFalse(parser.contains("private static func canonicalArguments"))
        XCTAssertFalse(parser.contains("normalizePullRequestArguments"))
        XCTAssertFalse(parser.contains("requiresNonEmptyArguments"))
        XCTAssertFalse(parser.contains("jsonObjectCandidates"))
        XCTAssertFalse(parser.contains("inlineCodeSpans"))
        XCTAssertFalse(normalizer.contains("normalizePullRequestArguments"))
        XCTAssertFalse(normalizer.contains("case ToolDefinition.gitPullRequestView.name"))
    }
}
