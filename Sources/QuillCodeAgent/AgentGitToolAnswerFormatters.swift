import Foundation
import QuillCodeCore
import QuillCodeTools

enum AgentGitToolAnswerFormatters {
    static func statusAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.gitStatus.name else {
            return nil
        }
        let output = AgentToolAnswerFormatterSupport.combinedOutput(result)
        guard !output.isEmpty else {
            return "Git status is clean."
        }
        return "Git status:\n\(AgentToolAnswerFormatters.truncated(output))"
    }

    static func diffAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.gitDiff.name else {
            return nil
        }
        let staged = AgentToolAnswerFormatterSupport.boolArgument("staged", in: call) ?? false
        let output = AgentToolAnswerFormatterSupport.combinedOutput(result)
        guard !output.isEmpty else {
            return staged ? "No staged git diff." : "No unstaged git diff."
        }
        let title = staged ? "Staged git diff" : "Git diff"
        return "\(title):\n\(AgentToolAnswerFormatters.truncated(output))"
    }

    static func worktreePruneAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.gitWorktreePrune.name else {
            return nil
        }
        return gitWorktreePruneAnswer(call: call, result: result)
    }

    static func worktreeCreateBranchAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.gitWorktreeCreateBranch.name,
              result.ok,
              let branch = AgentToolAnswerFormatterSupport.argument("branch", in: call)
        else { return nil }
        return "Created branch `\(branch)` in this worktree."
    }

    static func pullRequestReviewThreadsAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.gitPullRequestReviewThreads.name else {
            return nil
        }
        return pullRequestReviewThreadsAnswer(result.stdout)
    }

    private static func gitWorktreePruneAnswer(call: ToolCall, result: ToolResult) -> String {
        let dryRun = AgentToolAnswerFormatterSupport.boolArgument("dryRun", in: call) ?? false
        let output = AgentToolAnswerFormatterSupport.combinedOutput(result)
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
                AgentToolAnswerFormatters.truncated(output)
            ].joined(separator: "\n")
        }

        guard !lines.isEmpty else {
            return "Pruned stale worktree records. Git did not report any entries."
        }
        let count = staleWorktreeRecordCount(in: lines)
        return "Pruned \(count) stale worktree \(count == 1 ? "record" : "records").\n\(AgentToolAnswerFormatters.truncated(output))"
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
