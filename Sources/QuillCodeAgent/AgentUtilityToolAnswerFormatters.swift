import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

enum AgentUtilityToolAnswerFormatters {
    static func fileWriteAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.fileWrite.name else {
            return nil
        }
        if let path = AgentToolAnswerFormatterSupport.argument("path", in: call) {
            return "Wrote `\(path)`."
        }
        if let path = result.artifacts.first {
            return "Wrote `\(path)`."
        }
        return "Wrote the file."
    }

    static func applyPatchAnswer(
        call: ToolCall,
        result _: ToolResult,
        followUpReviewResult: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.applyPatch.name else {
            return nil
        }
        if let followUpReviewResult, !followUpReviewResult.ok {
            let details = [followUpReviewResult.error, followUpReviewResult.stderr.trimmedNonEmpty]
                .compactMap { $0 }
                .joined(separator: "\n")
            if details.isEmpty {
                return "Patch applied, but I could not refresh the review diff."
            }
            return "Patch applied, but I could not refresh the review diff:\n\(AgentToolAnswerFormatters.truncated(details))"
        }
        return followUpReviewResult == nil
            ? "Patch applied."
            : "Patch applied. Review the resulting diff below."
    }

    static func planUpdateAnswer(
        call: ToolCall,
        result _: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        call.name == ToolDefinition.planUpdate.name ? "Updated the task plan." : nil
    }

    static func handoffUpdateAnswer(
        call: ToolCall,
        result _: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        call.name == ToolDefinition.handoffUpdate.name ? "Updated the handoff summary." : nil
    }

    static func subagentsUpdateAnswer(
        call: ToolCall,
        result _: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        call.name == ToolDefinition.subagentsUpdate.name ? "Updated subagent progress." : nil
    }

    static func memoryRememberAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.memoryRemember.name else {
            return nil
        }
        if let output = try? JSONHelpers.decode(MemoryRememberToolOutput.self, from: result.stdout) {
            return "Saved memory: \(output.title). It will be included as background context in future turns."
        }
        return "Saved memory."
    }

    static func mcpReadResourceAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.mcpReadResource.name else {
            return nil
        }
        let output = result.stdout.trimmedNonEmpty
        return output.map { "MCP resource contents:\n\(AgentToolAnswerFormatters.truncated($0))" }
            ?? "MCP resource read completed with no text content."
    }

    static func mcpGetPromptAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.mcpGetPrompt.name else {
            return nil
        }
        let output = result.stdout.trimmedNonEmpty
        return output.map { "MCP prompt:\n\(AgentToolAnswerFormatters.truncated($0))" }
            ?? "MCP prompt loaded."
    }

    static func computerScreenshotAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.computerScreenshot.name,
              let screenshot = try? JSONHelpers.decode(ComputerScreenshotToolOutput.self, from: result.stdout)
        else {
            return nil
        }
        return "Captured a screenshot (\(screenshot.width) x \(screenshot.height))."
    }

    static func computerUseActionAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard ToolDefinition.computerUseDefinitions.contains(where: { $0.name == call.name }) else {
            return nil
        }
        let output = result.stdout.trimmedNonEmpty
        return output.map { "Computer Use completed: \($0)" } ?? "Computer Use action completed."
    }
}
