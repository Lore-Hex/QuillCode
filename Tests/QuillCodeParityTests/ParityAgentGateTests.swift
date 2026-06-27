import XCTest

final class ParityAgentGateTests: QuillCodeParityTestCase {
    func testAgentRunnerDelegatesFinalAnswerFormatting() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let builderText = try Self.agentSourceText(named: "AgentFinalAnswerBuilder.swift")
        let formatterText = try Self.agentSourceText(named: "AgentToolAnswerFormatters.swift")
        let supportText = try Self.agentSourceText(named: "AgentToolAnswerFormatterSupport.swift")
        let shellFormatterText = try Self.agentSourceText(named: "AgentShellToolAnswerFormatters.swift")
        let browserFormatterText = try Self.agentSourceText(named: "AgentBrowserToolAnswerFormatters.swift")
        let gitFormatterText = try Self.agentSourceText(named: "AgentGitToolAnswerFormatters.swift")
        let utilityFormatterText = try Self.agentSourceText(named: "AgentUtilityToolAnswerFormatters.swift")

        XCTAssertTrue(builderText.contains("enum AgentFinalAnswerBuilder"), "Tool-result final answer copy should live in a focused builder.")
        XCTAssertTrue(builderText.contains("static func finalAnswer"), "Final answer formatting should be directly testable.")
        XCTAssertTrue(builderText.contains("AgentToolAnswerFormatters.all"), "The top-level final-answer method should route through the formatter registry.")
        XCTAssertFalse(builderText.contains("import QuillCodeTools"), "The builder should not import tool modules once formatting has a separate owner.")
        XCTAssertTrue(formatterText.contains("enum AgentToolAnswerFormatters"), "Tool-specific final-answer summaries should live in a dedicated formatter owner.")
        XCTAssertTrue(formatterText.contains("static var all: [Formatter]"), "Tool-specific final answers should be registered instead of growing the top-level finalAnswer method.")
        XCTAssertTrue(formatterText.contains("AgentShellToolAnswerFormatters.shellRunAnswer"), "The registry should delegate shell copy to a focused formatter.")
        XCTAssertTrue(formatterText.contains("AgentBrowserToolAnswerFormatters.browserInspectAnswer"), "The registry should delegate browser copy to a focused formatter.")
        XCTAssertTrue(formatterText.contains("AgentGitToolAnswerFormatters.pullRequestReviewThreadsAnswer"), "The registry should delegate PR review-thread copy to a focused formatter.")
        XCTAssertTrue(formatterText.contains("AgentUtilityToolAnswerFormatters.memoryRememberAnswer"), "The registry should delegate utility tool copy to a focused formatter.")
        XCTAssertTrue(supportText.contains("enum AgentToolAnswerFormatterSupport"), "Shared formatter argument parsing should stay out of domain formatter files.")
        XCTAssertTrue(shellFormatterText.contains("ToolDefinition.shellRun.name"), "Shell final-answer special cases should live with shell formatters.")
        XCTAssertTrue(browserFormatterText.contains("ToolDefinition.browserInspect.name"), "Browser final-answer special cases should live with browser formatters.")
        XCTAssertTrue(gitFormatterText.contains("ToolDefinition.gitPullRequestReviewThreads.name"), "PR review-thread final-answer copy should live with git formatters.")
        XCTAssertTrue(utilityFormatterText.contains("ToolDefinition.memoryRemember.name"), "Memory final-answer copy should live with utility formatters.")
        XCTAssertFalse(formatterText.contains("private static func shellAnswer"), "The registry should not own shell-specific formatting logic.")
        XCTAssertFalse(formatterText.contains("PullRequestReviewThreadsResponse"), "The registry should not own PR response models.")
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

    func testAgentCancellationTelemetryLivesInFocusedRecorder() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let recorderText = try Self.agentSourceText(named: "AgentCancellationRecorder.swift")
        let streamingTests = try Self.agentTestSourceText(named: "AgentStreamingTests.swift")

        XCTAssertTrue(recorderText.contains("enum AgentCancellationRecorder"), "Agent cancellation transcript mutation should live in a focused recorder.")
        XCTAssertTrue(recorderText.contains("Stopped by user"), "Stopped-run copy should be centralized in the recorder.")
        XCTAssertTrue(agentText.contains("AgentCancellationRecorder.recordCancelledRun"), "AgentRunner should delegate cancellation transcript mutation.")
        XCTAssertFalse(agentText.contains(#""Stopped by user""#), "Agent.swift should not own stopped-run copy inline.")
        XCTAssertTrue(streamingTests.contains("testCancellingBeforeModelActionPublishesStoppedNotice"), "Agent tests should cover cancellation before a model action arrives.")
        XCTAssertTrue(streamingTests.contains("testCancellingRunningToolPublishesStoppedToolFailure"), "Agent tests should cover cancellation while a tool is active.")
    }

    func testAgentBehaviorTestsUseFocusedSuites() throws {
        let immediateTests = try Self.agentTestSourceText(named: "AgentImmediateActionTests.swift")
        let toolLoopTests = try Self.agentTestSourceText(named: "AgentToolLoopTests.swift")
        let streamingTests = try Self.agentTestSourceText(named: "AgentStreamingTests.swift")
        let pullRequestTests = try Self.agentTestSourceText(named: "MockLLMClientPullRequestTests.swift")
        let finalAnswerTests = try Self.agentTestSourceText(named: "AgentFinalAnswerBuilderTests.swift")
        let supportTests = try Self.agentTestSourceText(named: "AgentTestSupport.swift")

        XCTAssertTrue(immediateTests.contains("testRunWhoamiExecutesImmediately"), "Immediate command execution should live in focused agent action tests.")
        XCTAssertTrue(toolLoopTests.contains("testAgentContinuesAcrossMultipleToolCallsInOneTurn"), "Tool loop behavior should live in focused agent tool-loop tests.")
        XCTAssertTrue(streamingTests.contains("testStreamingToolActionReportsStatusAndExecutes"), "Streaming behavior should live in focused agent streaming tests.")
        XCTAssertTrue(pullRequestTests.contains("testPullRequestMergeUsesStructuredToolCall"), "Mock PR planning should live in focused mock PR tests.")
        XCTAssertTrue(finalAnswerTests.contains("testBrowserInspectFinalAnswerSummarizesPage"), "Final-answer copy should live in focused final-answer tests.")
        XCTAssertTrue(supportTests.contains("struct FixedToolLLMClient"), "Agent test fakes should be shared instead of duplicated across focused suites.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.packageRoot()
            .appendingPathComponent("Tests/QuillCodeAgentTests/AgentTests.swift")
            .path), "AgentTests.swift should not regrow as a broad mixed-behavior suite.")
    }
}
