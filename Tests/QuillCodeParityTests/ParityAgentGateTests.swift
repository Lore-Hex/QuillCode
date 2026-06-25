import XCTest

final class ParityAgentGateTests: QuillCodeParityTestCase {
    func testAgentRunnerDelegatesFinalAnswerFormatting() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let builderText = try Self.agentSourceText(named: "AgentFinalAnswerBuilder.swift")

        XCTAssertTrue(builderText.contains("enum AgentFinalAnswerBuilder"), "Tool-result final answer copy should live in a focused builder.")
        XCTAssertTrue(builderText.contains("static func finalAnswer"), "Final answer formatting should be directly testable.")
        XCTAssertTrue(builderText.contains("ToolDefinition.shellRun.name"), "Shell final-answer special cases should live in the builder.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserInspect.name"), "Browser final-answer special cases should live in the builder.")
        XCTAssertTrue(agentText.contains("AgentFinalAnswerBuilder.finalAnswer"), "AgentRunner should delegate final-answer formatting.")
        XCTAssertFalse(agentText.contains("private static func shellAnswer"), "AgentRunner should not own shell final-answer formatting.")
        XCTAssertFalse(agentText.contains("private static func browserInspectionAnswer"), "AgentRunner should not own browser final-answer formatting.")
    }

    func testMockLLMClientLivesOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let mockText = try Self.agentSourceText(named: "MockLLMClient.swift")
        let pullRequestPlannerText = try Self.agentSourceText(named: "MockPullRequestIntentPlanner.swift")
        let pullRequestExtractorText = try Self.agentSourceText(named: "MockPullRequestArgumentExtractor.swift")

        XCTAssertTrue(mockText.contains("public struct MockLLMClient"), "The deterministic mock LLM client should live in its own file.")
        XCTAssertTrue(mockText.contains("MockPullRequestIntentPlanner.toolCall"), "The mock LLM client should delegate PR-specific planning.")
        XCTAssertTrue(mockText.contains("AgentRunner.finalAnswer"), "Mock tool feedback should still reuse the production final-answer contract.")
        XCTAssertTrue(pullRequestPlannerText.contains("enum MockPullRequestIntentPlanner"), "Mock PR intent detection should live in a focused planner.")
        XCTAssertTrue(pullRequestPlannerText.contains("MockPullRequestArgumentExtractor.createArguments"), "Mock PR planner should delegate payload construction.")
        XCTAssertTrue(pullRequestExtractorText.contains("enum MockPullRequestArgumentExtractor"), "Mock PR payload construction should live in a focused extractor.")
        XCTAssertTrue(pullRequestExtractorText.contains("static func createArguments"), "Mock PR create argument extraction should stay out of intent routing.")
        XCTAssertFalse(agentText.contains("public struct MockLLMClient"), "Agent.swift should not own mock LLM planning.")
        XCTAssertFalse(agentText.contains("extractPullRequestArguments"), "Agent.swift should not own mock PR parsing heuristics.")
        XCTAssertFalse(mockText.contains("extractPullRequestArguments"), "MockLLMClient.swift should not own PR parsing heuristics.")
        XCTAssertFalse(mockText.contains("isPullRequestRequest"), "MockLLMClient.swift should not own PR intent detection.")
        XCTAssertFalse(pullRequestPlannerText.contains("static func createArguments"), "Mock PR planner should not own argument extraction.")
    }

    func testAgentStreamingHelpersLiveOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let streamingText = try Self.agentSourceText(named: "AgentActionStreaming.swift")

        XCTAssertTrue(streamingText.contains("public enum AgentActionStreamCollector"), "Streaming action collection should live in a focused helper.")
        XCTAssertTrue(streamingText.contains("public enum AgentActionStreamPreview"), "Partial assistant preview parsing should live with streaming helpers.")
        XCTAssertTrue(streamingText.contains("var rawActionText"), "Progressive stream accumulation should live with the stream collector.")
        XCTAssertTrue(streamingText.contains("AgentActionStreamPreview.visibleAssistantText"), "Stream collector should own draft-preview extraction.")
        XCTAssertTrue(agentText.contains("AgentActionStreamCollector.collect"), "AgentRunner should delegate streaming collection.")
        XCTAssertFalse(agentText.contains("public enum AgentActionStreamCollector"), "Agent.swift should not own streaming collection details.")
        XCTAssertFalse(agentText.contains("private static func partialJSONStringValue"), "Agent.swift should not own partial JSON preview parsing.")
        XCTAssertFalse(agentText.contains("AgentActionStreamPreview.visibleAssistantText"), "Agent.swift should not own streaming preview parsing.")
        XCTAssertFalse(agentText.contains("var rawActionText"), "Agent.swift should not own raw streaming accumulation.")
    }

    func testAgentToolStepRunnerLivesOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let runnerText = try Self.agentSourceText(named: "AgentToolStepRunner.swift")

        XCTAssertTrue(runnerText.contains("enum AgentToolStep"), "Tool-step state should live beside the extracted runner.")
        XCTAssertTrue(runnerText.contains("func runToolStep"), "Tool-step execution should live in a focused runner extension.")
        XCTAssertTrue(runnerText.contains("appendQueuedEvent"), "Tool lifecycle transcript events should be owned by the tool-step runner.")
        XCTAssertTrue(runnerText.contains("SafetyReview"), "Safety-review blocking copy should stay with tool-step execution.")
        XCTAssertTrue(agentText.contains("runToolStep("), "AgentRunner should delegate individual tool-step execution.")
        XCTAssertFalse(agentText.contains("private func runToolStep"), "Agent.swift should not own individual tool-step execution.")
        XCTAssertFalse(agentText.contains("kind: .toolQueued"), "Agent.swift should not own tool lifecycle event emission.")
        XCTAssertFalse(agentText.contains("Tool is not available in this workspace"), "Agent.swift should not own unavailable-tool result copy.")
    }
}
