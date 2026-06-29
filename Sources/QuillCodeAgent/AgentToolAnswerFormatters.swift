import QuillCodeCore

enum AgentToolAnswerFormatters {
    typealias Formatter = (ToolCall, ToolResult, ToolResult?) -> String?

    static var all: [Formatter] {
        [
            AgentUtilityToolAnswerFormatters.fileReadAnswer,
            AgentUtilityToolAnswerFormatters.fileWriteAnswer,
            AgentUtilityToolAnswerFormatters.applyPatchAnswer,
            AgentGitToolAnswerFormatters.statusAnswer,
            AgentGitToolAnswerFormatters.diffAnswer,
            AgentGitToolAnswerFormatters.worktreePruneAnswer,
            AgentGitToolAnswerFormatters.pullRequestReviewThreadsAnswer,
            AgentUtilityToolAnswerFormatters.planUpdateAnswer,
            AgentUtilityToolAnswerFormatters.handoffUpdateAnswer,
            AgentUtilityToolAnswerFormatters.subagentsUpdateAnswer,
            AgentUtilityToolAnswerFormatters.memoryRememberAnswer,
            AgentShellToolAnswerFormatters.shellRunAnswer,
            AgentBrowserToolAnswerFormatters.browserInspectAnswer,
            AgentBrowserToolAnswerFormatters.browserOpenAnswer,
            AgentUtilityToolAnswerFormatters.mcpReadResourceAnswer,
            AgentUtilityToolAnswerFormatters.mcpGetPromptAnswer,
            AgentUtilityToolAnswerFormatters.computerScreenshotAnswer,
            AgentUtilityToolAnswerFormatters.computerUseActionAnswer
        ]
    }

    static func truncated(_ text: String, maxCharacters: Int = 2_000) -> String {
        guard text.count > maxCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<end])\n\n[truncated in chat; full output is in the tool card]"
    }
}
