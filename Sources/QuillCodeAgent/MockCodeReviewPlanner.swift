import QuillCodeCore

enum MockCodeReviewPlanner {
    static func action(
        thread: ChatThread,
        prompt: String,
        tools: [ToolDefinition]
    ) -> AgentAction? {
        guard tools.contains(where: { $0.name == ToolDefinition.codeReviewSubmit.name }) else {
            return nil
        }

        let completedToolCount = thread.messages.lazy.filter { $0.role == .tool }.count
        if let scopedDiff = scopedDiffArguments(in: prompt) {
            if completedToolCount == 0,
               tools.contains(where: { $0.name == ToolDefinition.gitDiff.name }) {
                return .tool(ToolCall(
                    name: ToolDefinition.gitDiff.name,
                    argumentsJSON: ToolArguments.json(scopedDiff)
                ))
            }
            return completedToolCount == 1 ? submission() : .say("Review complete.")
        }

        switch completedToolCount {
        case 0 where tools.contains(where: { $0.name == ToolDefinition.gitStatus.name }):
            return .tool(ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}"))
        case 1 where tools.contains(where: { $0.name == ToolDefinition.gitDiff.name }):
            return .tool(ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"))
        case 2 where tools.contains(where: { $0.name == ToolDefinition.gitDiff.name }):
            return .tool(ToolCall(
                name: ToolDefinition.gitDiff.name,
                argumentsJSON: ToolArguments.json(["staged": true])
            ))
        case 3:
            return submission()
        default:
            return .say("Review complete.")
        }
    }

    private static func submission() -> AgentAction {
        .tool(ToolCall(
            name: ToolDefinition.codeReviewSubmit.name,
            argumentsJSON: ToolArguments.json([
                "summary": "No actionable findings in the deterministic mock review.",
                "findings": []
            ])
        ))
    }

    private static func scopedDiffArguments(in prompt: String) -> [String: String]? {
        for key in ["baseBranch", "commit"] {
            let marker = "{\"\(key)\":\""
            guard let start = prompt.range(of: marker) else { continue }
            let valueStart = start.upperBound
            guard let end = prompt[valueStart...].range(of: "\"}") else { continue }
            return [key: String(prompt[valueStart..<end.lowerBound])]
        }
        return nil
    }
}
