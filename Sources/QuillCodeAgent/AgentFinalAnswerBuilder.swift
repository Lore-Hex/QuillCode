import Foundation
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

enum AgentFinalAnswerBuilder {
    private typealias ToolAnswerFormatter = (ToolCall, ToolResult, ToolResult?) -> String?

    static func finalAnswer(
        for call: ToolCall,
        result: ToolResult,
        followUpReviewResult: ToolResult? = nil
    ) -> String {
        if !result.ok {
            let details = [result.error, result.stderr.trimmedNonEmpty]
                .compactMap { $0 }
                .joined(separator: "\n")
            if details.isEmpty {
                return "Command failed."
            }
            return "Command failed:\n\(truncated(details))"
        }

        for formatter in toolAnswerFormatters {
            if let answer = formatter(call, result, followUpReviewResult) {
                return answer
            }
        }

        return defaultAnswer(result)
    }

    private static var toolAnswerFormatters: [ToolAnswerFormatter] {
        [
            fileWriteAnswer,
            applyPatchAnswer,
            worktreePruneAnswer,
            pullRequestReviewThreadsAnswer,
            planUpdateAnswer,
            memoryRememberAnswer,
            shellRunAnswer,
            browserInspectAnswer,
            browserOpenAnswer,
            mcpReadResourceAnswer,
            mcpGetPromptAnswer,
            computerScreenshotAnswer,
            computerUseActionAnswer
        ]
    }

    private static func defaultAnswer(_ result: ToolResult) -> String {
        let output = [result.stdout, result.stderr]
            .compactMap(\.trimmedNonEmpty)
            .joined(separator: "\n")
        if output.isEmpty {
            return "Done."
        }
        return "Output:\n\(truncated(output))"
    }

    private static func fileWriteAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.fileWrite.name else {
            return nil
        }
        if let path = argument("path", in: call) {
            return "Wrote `\(path)`."
        }
        if let path = result.artifacts.first {
            return "Wrote `\(path)`."
        }
        return "Wrote the file."
    }

    private static func applyPatchAnswer(
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
            return "Patch applied, but I could not refresh the review diff:\n\(truncated(details))"
        }
        return followUpReviewResult == nil
            ? "Patch applied."
            : "Patch applied. Review the resulting diff below."
    }

    private static func worktreePruneAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.gitWorktreePrune.name else {
            return nil
        }
        return gitWorktreePruneAnswer(call: call, result: result)
    }

    private static func pullRequestReviewThreadsAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.gitPullRequestReviewThreads.name else {
            return nil
        }
        return pullRequestReviewThreadsAnswer(result.stdout)
    }

    private static func planUpdateAnswer(
        call: ToolCall,
        result _: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        call.name == ToolDefinition.planUpdate.name ? "Updated the task plan." : nil
    }

    private static func memoryRememberAnswer(
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

    private static func shellRunAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.shellRun.name,
              let command = argument("cmd", in: call)
        else {
            return nil
        }
        return shellAnswer(command: command, result: result)
    }

    private static func browserInspectAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.browserInspect.name,
              let inspection = try? JSONHelpers.decode(BrowserInspectionToolOutput.self, from: result.stdout)
        else {
            return nil
        }
        return browserInspectionAnswer(inspection)
    }

    private static func browserOpenAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.browserOpen.name,
              let inspection = try? JSONHelpers.decode(BrowserInspectionToolOutput.self, from: result.stdout)
        else {
            return nil
        }
        return browserOpenAnswer(inspection)
    }

    private static func mcpReadResourceAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.mcpReadResource.name else {
            return nil
        }
        let output = result.stdout.trimmedNonEmpty
        return output.map { "MCP resource contents:\n\(truncated($0))" }
            ?? "MCP resource read completed with no text content."
    }

    private static func mcpGetPromptAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.mcpGetPrompt.name else {
            return nil
        }
        let output = result.stdout.trimmedNonEmpty
        return output.map { "MCP prompt:\n\(truncated($0))" }
            ?? "MCP prompt loaded."
    }

    private static func computerScreenshotAnswer(
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

    private static func computerUseActionAnswer(
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

    private static func browserInspectionAnswer(_ inspection: BrowserInspectionToolOutput) -> String {
        var lines = [
            "Inspected `\(inspection.title)` at \(inspection.url).",
            "Inspection depth: \(inspection.inspectionDepth.label).",
            inspection.summary
        ]
        if !inspection.outline.isEmpty {
            lines.append("Outline: \(inspection.outline.prefix(5).joined(separator: "; ")).")
        }
        if let textSnippet = inspection.textSnippet?.trimmedNonEmpty {
            lines.append("Text: \(truncated(textSnippet, maxCharacters: 320))")
        }
        if !inspection.comments.isEmpty {
            lines.append("Browser comments: \(inspection.comments.map(\.text).prefix(3).joined(separator: "; ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func browserOpenAnswer(_ inspection: BrowserInspectionToolOutput) -> String {
        var lines = [
            "Opened `\(inspection.title)` at \(inspection.url).",
            inspection.summary
        ]
        if !inspection.outline.isEmpty {
            lines.append("Outline: \(inspection.outline.prefix(5).joined(separator: "; ")).")
        }
        if let textSnippet = inspection.textSnippet?.trimmedNonEmpty {
            lines.append("Text: \(truncated(textSnippet, maxCharacters: 320))")
        }
        return lines.joined(separator: "\n")
    }

    private static func shellAnswer(command: String, result: ToolResult) -> String? {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedCommand.lowercased()
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = stdout.isEmpty ? stderr : stdout

        if lower == "whoami" {
            guard !stdout.isEmpty else { return "The command ran, but did not print a user name." }
            return "You are `\(firstLine(stdout))` in this workspace."
        }

        if lower.contains("openclaw") && (lower.contains("command -v") || lower.contains("which ")) {
            let firstLine = firstLine(output)
            if firstLine.isEmpty || firstLine == "not found" {
                return "openclaw is not installed or is not on PATH."
            }
            return "openclaw is installed at `\(firstLine)`."
        }

        if lower.hasPrefix("df ") || lower.contains(" df ") || lower.contains("df -h") {
            guard !output.isEmpty else { return "Disk usage command completed with no output." }
            return "Disk usage:\n\(truncated(output))"
        }

        return nil
    }

    private static func gitWorktreePruneAnswer(call: ToolCall, result: ToolResult) -> String {
        let dryRun = boolArgument("dryRun", in: call) ?? false
        let output = [result.stdout, result.stderr]
            .compactMap(\.trimmedNonEmpty)
            .joined(separator: "\n")
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if dryRun {
            guard !lines.isEmpty else {
                return "No stale worktree records found."
            }
            let count = staleWorktreeRecordCount(in: lines)
            return [
                "Found \(count) stale worktree \(count == 1 ? "record" : "records").",
                "Run `/worktree prune` to remove \(count == 1 ? "it" : "them").",
                truncated(output)
            ].joined(separator: "\n")
        }

        guard !lines.isEmpty else {
            return "Pruned stale worktree records. Git did not report any entries."
        }
        let count = staleWorktreeRecordCount(in: lines)
        return "Pruned \(count) stale worktree \(count == 1 ? "record" : "records").\n\(truncated(output))"
    }

    private static func pullRequestReviewThreadsAnswer(_ output: String) -> String? {
        guard let response = try? JSONHelpers.decode(PullRequestReviewThreadsResponse.self, from: output),
              let threads = response.data?.repository?.pullRequest?.reviewThreads.nodes
        else {
            return nil
        }
        guard !threads.isEmpty else {
            return "No pull request review threads found."
        }

        let unresolvedCount = threads.filter { !$0.isResolved }.count
        let resolvedCount = threads.count - unresolvedCount
        let threadNoun = plural("thread", threads.count)
        var lines = [
            "Found \(threads.count) review \(threadNoun): \(unresolvedCount) unresolved, \(resolvedCount) resolved."
        ]
        lines.append(contentsOf: threads.prefix(6).map(reviewThreadSummary))
        if threads.count > 6 {
            lines.append("Showing 6 of \(threads.count). Use the tool card for the full thread list.")
        }
        return lines.joined(separator: "\n")
    }

    private static func reviewThreadSummary(_ thread: PullRequestReviewThreadNode) -> String {
        let state = thread.isResolved ? "resolved" : "unresolved"
        let outdated = thread.isOutdated ? ", outdated" : ""
        let location = reviewThreadLocation(thread)
        let firstComment = thread.comments.nodes.first
        let commentID = firstComment.flatMap { comment in
            comment.databaseId.map { "comment #\($0)" } ?? comment.id.trimmedNonEmpty
        }
        let author = firstComment?.author.map { " by \($0.login)" } ?? ""
        let snippet = firstComment.flatMap(\.body.trimmedNonEmpty).map {
            " - \(shortened(oneLineSnippet($0), maxCharacters: 160))"
        } ?? ""
        let commentSuffix = commentID.map { "; \($0)\(author)" } ?? ""
        return "- \(state)\(outdated) \(location): thread `\(thread.id)`\(commentSuffix)\(snippet)"
    }

    private static func reviewThreadLocation(_ thread: PullRequestReviewThreadNode) -> String {
        guard let path = thread.path?.trimmedNonEmpty else {
            return "unknown location"
        }
        if let startLine = thread.startLine, let line = thread.line, startLine != line {
            return "`\(path):\(startLine)-\(line)`"
        }
        if let line = thread.line ?? thread.startLine {
            return "`\(path):\(line)`"
        }
        return "`\(path)`"
    }

    private static func oneLineSnippet(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func plural(_ noun: String, _ count: Int) -> String {
        count == 1 ? noun : "\(noun)s"
    }

    private static func shortened(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<end])..."
    }

    private static func staleWorktreeRecordCount(in lines: [String]) -> Int {
        let removingLines = lines.filter { line in
            let lower = line.lowercased()
            return lower.hasPrefix("removing ") || lower.contains(": gitdir file points")
        }
        return removingLines.isEmpty ? lines.count : removingLines.count
    }

    private static func argument(_ key: String, in call: ToolCall) -> String? {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolArgument(_ key: String, in call: ToolCall) -> Bool? {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key]
        else {
            return nil
        }
        if let bool = value as? Bool {
            return bool
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private static func truncated(_ text: String, maxCharacters: Int = 2_000) -> String {
        guard text.count > maxCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<end])\n\n[truncated in chat; full output is in the tool card]"
    }
}

private struct PullRequestReviewThreadsResponse: Decodable {
    struct Payload: Decodable {
        let repository: Repository?
    }

    struct Repository: Decodable {
        let pullRequest: PullRequest?
    }

    struct PullRequest: Decodable {
        let reviewThreads: ReviewThreads
    }

    struct ReviewThreads: Decodable {
        let nodes: [PullRequestReviewThreadNode]
    }

    let data: Payload?
}

private struct PullRequestReviewThreadNode: Decodable {
    struct Comments: Decodable {
        let nodes: [Comment]
    }

    struct Comment: Decodable {
        struct Author: Decodable {
            let login: String
        }

        let id: String
        let databaseId: Int?
        let body: String
        let author: Author?
    }

    let id: String
    let isResolved: Bool
    let isOutdated: Bool
    let path: String?
    let line: Int?
    let startLine: Int?
    let comments: Comments
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
