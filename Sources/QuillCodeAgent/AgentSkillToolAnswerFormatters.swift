import QuillCodeCore
import QuillCodeTools

enum AgentSkillToolAnswerFormatters {
    static func skillLoadAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.skillLoad.name else {
            return nil
        }
        let name = AgentToolAnswerFormatterSupport.argument("name", in: call) ?? "the skill"
        if !result.ok {
            let details = AgentToolAnswerFormatterSupport.failureDetail(result)
            return details.isEmpty
                ? "Could not load skill `\(name)`."
                : "Could not load skill `\(name)`: \(AgentToolAnswerFormatters.truncated(details))"
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            return "Loaded skill `\(name)`, but it had no content."
        }
        return AgentToolAnswerFormatters.truncated(output)
    }
}
