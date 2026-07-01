import XCTest

final class ParityAgentBehaviorSuiteGateTests: QuillCodeParityTestCase {
    func testAgentBehaviorTestsUseFocusedSuites() throws {
        let immediateSupport = try Self.agentTestSourceText(named: "AgentImmediateActionTestSupport.swift")
        let immediateShellTests = try Self.agentTestSourceText(named: "AgentImmediateShellActionTests.swift")
        let immediateGitTests = try Self.agentTestSourceText(named: "AgentImmediateGitActionTests.swift")
        let immediateFileTests = try Self.agentTestSourceText(named: "AgentImmediateFileActionTests.swift")
        let immediateNegationTests = try Self.agentTestSourceText(named: "AgentImmediateNegationTests.swift")
        let toolLoopTests = try Self.agentTestSourceText(named: "AgentToolLoopTests.swift")
        let streamingTests = try Self.agentTestSourceText(named: "AgentStreamingTests.swift")
        let pullRequestTests = try Self.agentTestSourceText(named: "MockLLMClientPullRequestTests.swift")
        let finalAnswerTests = try Self.agentTestSourceText(named: "AgentFinalAnswerBuilderTests.swift")
        let supportTests = try Self.agentTestSourceText(named: "AgentTestSupport.swift")

        Self.assertSource(immediateShellTests, contains: "testRunWhoamiExecutesImmediately")
        Self.assertSource(immediateGitTests, contains: "testCommitChangesExecutesImmediately")
        Self.assertSource(immediateFileTests, contains: "testMakeHelloWorldFileExecutesImmediately")
        Self.assertSource(immediateNegationTests, contains: "testNegatedWhoamiDoesNotPreflight")
        Self.assertSource(immediateSupport, contains: "assertSingleSuccessfulToolResult")
        Self.assertSource(toolLoopTests, contains: "testAgentContinuesAcrossMultipleToolCallsInOneTurn")
        Self.assertSource(streamingTests, contains: "testStreamingToolActionReportsStatusAndExecutes")
        Self.assertSource(pullRequestTests, contains: "testPullRequestMergeUsesStructuredToolCall")
        Self.assertSource(finalAnswerTests, contains: "testBrowserInspectFinalAnswerSummarizesPage")
        Self.assertSource(supportTests, contains: "struct FixedToolLLMClient")

        for retiredSuite in [
            "Tests/QuillCodeAgentTests/AgentImmediateActionTests.swift",
            "Tests/QuillCodeAgentTests/AgentTests.swift"
        ] {
            let retiredFile = Self.packageRoot().appendingPathComponent(retiredSuite)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: retiredFile.path),
                "\(retiredSuite) should not regrow as a broad mixed-behavior suite."
            )
        }
    }
}
