import XCTest

final class ParityTrustedRouterGateTests: QuillCodeParityTestCase {
    func testTrustedRouterActionParserLivesOutsideTransportClient() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let parserText = try Self.agentSourceText(named: "AgentActionJSONParser.swift")
        let extractorText = try Self.agentSourceText(named: "AgentActionJSONExtractor.swift")
        let recoveryText = try Self.agentSourceText(named: "AgentShellCommandRecovery.swift")
        let normalizerText = try Self.agentSourceText(named: "AgentToolArgumentNormalizer.swift")

        XCTAssertTrue(parserText.contains("public enum AgentActionJSONParser"), "Action JSON parsing should live in a focused parser file.")
        XCTAssertTrue(normalizerText.contains("enum AgentToolArgumentNormalizer"), "Tool argument normalization should live in a focused normalizer.")
        XCTAssertTrue(normalizerText.contains("canonicalArguments"), "The normalizer should own canonical argument construction.")
        XCTAssertTrue(parserText.contains("AgentToolArgumentNormalizer.canonicalArguments"), "Action JSON parsing should delegate canonical argument construction.")
        XCTAssertTrue(parserText.contains("AgentActionJSONExtractor.actionObject"), "Action JSON parsing should delegate messy JSON extraction.")
        XCTAssertTrue(normalizerText.contains("AgentShellCommandRecovery.explicitCommand"), "Tool argument normalization should delegate malformed shell recovery.")
        XCTAssertTrue(extractorText.contains("enum AgentActionJSONExtractor"), "JSON object scanning should live in a focused helper.")
        XCTAssertTrue(recoveryText.contains("enum AgentShellCommandRecovery"), "Malformed shell-command recovery should live in a focused helper.")
        XCTAssertTrue(clientText.contains("AgentActionStreamCollector.collect"), "TrustedRouter client should delegate action collection/parsing.")
        XCTAssertFalse(clientText.contains("public enum AgentActionJSONParser"), "TrustedRouter transport should not own action parsing.")
        XCTAssertFalse(clientText.contains("canonicalArguments"), "TrustedRouter transport should not own tool argument normalization.")
        XCTAssertFalse(parserText.contains("private static func canonicalArguments"), "Action parser should not own tool argument normalization details.")
        XCTAssertFalse(parserText.contains("normalizePullRequestArguments"), "Action parser should not own pull request argument alias policy.")
        XCTAssertFalse(parserText.contains("requiresNonEmptyArguments"), "Action parser should not own tool minimum-argument policy.")
        XCTAssertFalse(parserText.contains("jsonObjectCandidates"), "Action parser should not own JSON-object scanning.")
        XCTAssertFalse(parserText.contains("inlineCodeSpans"), "Action parser should not own prose shell command recovery.")
        XCTAssertFalse(clientText.contains("AgentShellCommandRecovery"), "TrustedRouter transport should not own malformed-output recovery.")
        XCTAssertFalse(clientText.contains("jsonObjectCandidates"), "TrustedRouter transport should not own JSON-object extraction.")
    }

    func testTrustedRouterPromptBuilderLivesOutsideTransportClient() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let builderText = try Self.agentSourceText(named: "TrustedRouterPromptBuilder.swift")

        XCTAssertTrue(builderText.contains("public struct TrustedRouterPromptBuilder"), "Prompt rendering should live in a focused builder.")
        XCTAssertTrue(builderText.contains("historyLimit"), "Prompt history policy should stay with the prompt builder.")
        XCTAssertTrue(builderText.contains("systemPrompt(tools"), "System prompt copy should stay with the prompt builder.")
        XCTAssertTrue(builderText.contains("projectInstructionsPrompt"), "Project instruction formatting should stay with the prompt builder.")
        XCTAssertTrue(builderText.contains("memoryPrompt"), "Memory formatting should stay with the prompt builder.")
        XCTAssertTrue(clientText.contains("promptBuilder.messages"), "TrustedRouter client should delegate message construction.")
        XCTAssertFalse(clientText.contains("systemPrompt(tools"), "TrustedRouter transport should not own system prompt copy.")
        XCTAssertFalse(clientText.contains("projectInstructionsPrompt"), "TrustedRouter transport should not own project instruction formatting.")
        XCTAssertFalse(clientText.contains("memoryPrompt"), "TrustedRouter transport should not own memory formatting.")
        XCTAssertFalse(clientText.contains("thread.messages.suffix"), "TrustedRouter transport should not own message history projection.")
    }

    func testTrustedRouterAPIKeyResolutionLivesInFocusedResolver() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClientText = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")
        let resolverText = try Self.agentSourceText(named: "TrustedRouterAPIKeyResolver.swift")

        XCTAssertTrue(resolverText.contains("public struct TrustedRouterAPIKeyResolver"), "TrustedRouter API-key resolution should live in a focused helper.")
        XCTAssertTrue(resolverText.contains("apiKeyOverride"), "Developer override handling should stay with the resolver.")
        XCTAssertTrue(resolverText.contains("sessionStore?.apiKey()"), "Session-store fallback should stay with the resolver.")
        XCTAssertTrue(resolverText.contains("nonEmptyKey"), "Whitespace trimming should stay with the resolver.")
        XCTAssertTrue(clientText.contains("TrustedRouterAPIKeyResolver("), "TrustedRouter clients should delegate key resolution.")
        XCTAssertTrue(safetyClientText.contains("TrustedRouterAPIKeyResolver("), "TrustedRouter safety clients should delegate key resolution.")
        XCTAssertFalse(clientText.contains("trimmingCharacters(in: .whitespacesAndNewlines)"), "TrustedRouter clients should not duplicate key trimming.")
        XCTAssertFalse(clientText.contains("sessionStore?.apiKey()"), "TrustedRouter clients should not duplicate session-store fallback.")
        XCTAssertFalse(safetyClientText.contains("sessionStore?.apiKey()"), "TrustedRouter safety clients should not duplicate session-store fallback.")
    }

    func testTrustedRouterSafetyClientLivesOutsideActionTransportFile() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClientText = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")

        XCTAssertTrue(safetyClientText.contains("public struct TrustedRouterSafetyModelClient"), "TrustedRouter safety-review transport should live in its own file.")
        XCTAssertTrue(safetyClientText.contains("SafetyModelClient"), "The safety transport file should own the SafetyModelClient conformance.")
        XCTAssertTrue(safetyClientText.contains("Return only the requested JSON object."), "Safety-review JSON response framing should live with the safety transport.")
        XCTAssertFalse(clientText.contains("TrustedRouterSafetyModelClient"), "TrustedRouter action transport should not also own the safety-review client.")
        XCTAssertFalse(clientText.contains("SafetyModelClient"), "TrustedRouter action transport should not import or conform to safety protocols.")
    }

    func testTrustedRouterChatParametersLiveOutsideTransportClients() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClientText = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")
        let parametersText = try Self.agentSourceText(named: "TrustedRouterChatParameters.swift")

        XCTAssertTrue(parametersText.contains("public enum TrustedRouterChatParameters"), "Shared TrustedRouter chat request parameters should live in a focused catalog.")
        XCTAssertTrue(parametersText.contains("\"response_format\""), "JSON response-format payload should stay in the parameter catalog.")
        XCTAssertTrue(clientText.contains("TrustedRouterChatParameters.jsonObjectResponse"), "Action transport should use shared JSON response parameters.")
        XCTAssertTrue(safetyClientText.contains("TrustedRouterChatParameters.jsonObjectResponse"), "Safety transport should use shared JSON response parameters.")
        XCTAssertFalse(clientText.contains("\"response_format\""), "Action transport should not own raw response-format payloads.")
        XCTAssertFalse(safetyClientText.contains("\"response_format\""), "Safety transport should not own raw response-format payloads.")
        XCTAssertFalse(safetyClientText.contains("TrustedRouterLLMClient."), "Safety transport should not depend on the action transport type.")
    }
}
