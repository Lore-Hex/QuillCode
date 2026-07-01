import XCTest

final class ParityAgentMockPlanningGateTests: QuillCodeParityTestCase {
    func testMockLLMClientLivesOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let mockText = try Self.agentSourceText(named: "MockLLMClient.swift")
        let downloadParserText = try Self.agentSourceText(named: "AgentDownloadRequestParser.swift")
        let pullRequestPlannerText = try Self.agentSourceText(named: "MockPullRequestIntentPlanner.swift")
        let pullRequestExtractorText = try Self.agentSourceText(named: "MockPullRequestArgumentExtractor.swift")

        Self.assertSource(mockText, containsAll: [
            "public struct MockLLMClient",
            "MockPullRequestIntentPlanner.toolCall",
            "AgentDownloadRequestParser.shellCommand",
            "AgentRunner.finalAnswer"
        ])
        Self.assertSource(downloadParserText, contains: "enum AgentDownloadRequestParser")
        Self.assertSource(pullRequestPlannerText, containsAll: [
            "enum MockPullRequestIntentPlanner",
            "MockPullRequestArgumentExtractor.createArguments"
        ])
        Self.assertSource(pullRequestExtractorText, containsAll: [
            "enum MockPullRequestArgumentExtractor",
            "static func createArguments"
        ])
        Self.assertSource(agentText, excludesAll: [
            "public struct MockLLMClient",
            "extractPullRequestArguments"
        ])
        Self.assertSource(mockText, excludesAll: [
            "downloadCommand(",
            "extractDownloadTarget",
            "extractPullRequestArguments",
            "isPullRequestRequest"
        ])
        Self.assertSource(pullRequestPlannerText, excludes: "static func createArguments")
    }
}
