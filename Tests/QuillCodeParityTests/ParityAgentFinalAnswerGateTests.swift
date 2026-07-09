import XCTest

final class ParityAgentFinalAnswerGateTests: QuillCodeParityTestCase {
    func testAgentRunnerDelegatesFinalAnswerFormatting() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let builderText = try Self.agentSourceText(named: "AgentFinalAnswerBuilder.swift")
        let formatterText = try Self.agentSourceText(named: "AgentToolAnswerFormatters.swift")
        let supportText = try Self.agentSourceText(named: "AgentToolAnswerFormatterSupport.swift")
        let shellFormatterText = try Self.agentSourceText(named: "AgentShellToolAnswerFormatters.swift")
        let browserFormatterText = try Self.agentSourceText(named: "AgentBrowserToolAnswerFormatters.swift")
        let gitFormatterText = try Self.agentSourceText(named: "AgentGitToolAnswerFormatters.swift")
        let utilityFormatterText = try Self.agentSourceText(named: "AgentUtilityToolAnswerFormatters.swift")

        Self.assertSource(builderText, containsAll: [
            "enum AgentFinalAnswerBuilder",
            "static func finalAnswer",
            "AgentToolAnswerFormatters.all"
        ])
        Self.assertSource(builderText, excludes: "import QuillCodeTools")
        Self.assertSource(formatterText, containsAll: [
            "enum AgentToolAnswerFormatters",
            "static var all: [Formatter]",
            "AgentShellToolAnswerFormatters.shellRunAnswer",
            "AgentBrowserToolAnswerFormatters.browserInspectAnswer",
            "AgentBrowserToolAnswerFormatters.browserActionAnswer",
            "AgentBrowserToolAnswerFormatters.browserScriptAnswer",
            "AgentGitToolAnswerFormatters.pullRequestReviewThreadsAnswer",
            "AgentUtilityToolAnswerFormatters.memoryRememberAnswer"
        ])
        Self.assertSource(formatterText, excludesAll: [
            "private static func shellAnswer",
            "PullRequestReviewThreadsResponse"
        ])
        Self.assertSource(supportText, contains: "enum AgentToolAnswerFormatterSupport")
        Self.assertSource(shellFormatterText, contains: "ToolDefinition.shellRun.name")
        Self.assertSource(browserFormatterText, contains: "ToolDefinition.browserInspect.name")
        Self.assertSource(browserFormatterText, contains: "ToolDefinition.browserClick.name")
        Self.assertSource(browserFormatterText, contains: "ToolDefinition.browserType.name")
        Self.assertSource(browserFormatterText, contains: "ToolDefinition.browserScript.name")
        Self.assertSource(gitFormatterText, contains: "ToolDefinition.gitPullRequestReviewThreads.name")
        Self.assertSource(utilityFormatterText, contains: "ToolDefinition.memoryRemember.name")
        Self.assertSource(agentText, contains: "AgentFinalAnswerBuilder.finalAnswer")
        Self.assertSource(agentText, excludesAll: [
            "private static func shellAnswer",
            "private static func browserInspectionAnswer"
        ])
    }
}
