import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspacePullRequestReviewDraftRunPlan: Sendable, Hashable {
    let inlineCommentCalls: [ToolCall]
    let reviewCall: ToolCall

    var calls: [ToolCall] {
        inlineCommentCalls + [reviewCall]
    }

    func finalStatus(for results: [WorkspaceRecordedToolResult]) -> String {
        results.allSatisfy(\.result.ok)
            ? TopBarAgentStatusLabel.idle
            : TopBarAgentStatusLabel.failed
    }
}

enum WorkspacePullRequestReviewDraftToolCallPlanner {
    static func toolCall(for draft: WorkspacePullRequestReviewDraftSurface) -> ToolCall? {
        guard draft.canSubmit else { return nil }
        var arguments: [String: Any] = [
            "action": draft.action.rawValue
        ]
        if let selector = draft.normalizedSelector {
            arguments["selector"] = selector
        }
        let body = draft.normalizedBody
        if !body.isEmpty {
            arguments["body"] = body
        }
        return ToolCall(
            name: ToolDefinition.gitPullRequestReview.name,
            argumentsJSON: ToolArguments.json(arguments)
        )
    }

    static func runPlan(for draft: WorkspacePullRequestReviewDraftSurface) -> WorkspacePullRequestReviewDraftRunPlan? {
        guard let reviewCall = toolCall(for: draft) else {
            return nil
        }
        return WorkspacePullRequestReviewDraftRunPlan(
            inlineCommentCalls: inlineCommentCalls(for: draft),
            reviewCall: reviewCall
        )
    }

    private static func inlineCommentCalls(for draft: WorkspacePullRequestReviewDraftSurface) -> [ToolCall] {
        draft.selectedInlineComments.map { comment in
            var arguments: [String: Any] = [
                "path": comment.path,
                "line": comment.line,
                "side": comment.side,
                "body": comment.normalizedBody
            ]
            if let selector = draft.normalizedSelector {
                arguments["selector"] = selector
            }
            if let startLine = comment.startLine {
                arguments["startLine"] = startLine
                arguments["startSide"] = comment.side
            }
            return ToolCall(
                name: ToolDefinition.gitPullRequestReviewComment.name,
                argumentsJSON: ToolArguments.json(arguments)
            )
        }
    }
}

@MainActor
public extension QuillCodeWorkspaceModel {
    func presentPullRequestReviewDraft() {
        let inlineComments = WorkspacePullRequestReviewDraftCommentSurface.collect(from: surface().review)
        pullRequestReviewDraft = WorkspacePullRequestReviewDraftSurface(inlineComments: inlineComments)
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    func updatePullRequestReviewDraft(_ draft: WorkspacePullRequestReviewDraftSurface) {
        pullRequestReviewDraft = draft
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    func cancelPullRequestReviewDraft() {
        pullRequestReviewDraft = nil
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    @discardableResult
    func submitPullRequestReviewDraft(workspaceRoot: URL) -> Bool {
        guard let draft = pullRequestReviewDraft else {
            return false
        }
        guard let plan = WorkspacePullRequestReviewDraftToolCallPlanner.runPlan(for: draft) else {
            setLastError("Review body is required for comment and request changes.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }
        pullRequestReviewDraft = nil
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        var results: [WorkspaceRecordedToolResult] = []
        for call in plan.inlineCommentCalls {
            let result = runToolCall(call, workspaceRoot: workspaceRoot)
            results.append(WorkspaceRecordedToolResult(call: call, result: result))
            guard result.ok else {
                refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
                return false
            }
        }
        let reviewResult = runToolCall(plan.reviewCall, workspaceRoot: workspaceRoot)
        results.append(WorkspaceRecordedToolResult(call: plan.reviewCall, result: reviewResult))
        let finalStatus = plan.finalStatus(for: results)
        refreshTopBar(agentStatus: finalStatus)
        return finalStatus == TopBarAgentStatusLabel.idle
    }
}
