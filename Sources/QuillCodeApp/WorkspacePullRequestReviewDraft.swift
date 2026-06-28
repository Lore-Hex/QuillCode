import Foundation
import QuillCodeCore
import QuillCodeTools

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
}

@MainActor
public extension QuillCodeWorkspaceModel {
    func presentPullRequestReviewDraft() {
        pullRequestReviewDraft = WorkspacePullRequestReviewDraftSurface()
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
        guard let call = WorkspacePullRequestReviewDraftToolCallPlanner.toolCall(for: draft) else {
            setLastError("Review body is required for comment and request changes.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }
        pullRequestReviewDraft = nil
        setLastError(nil)
        let result = runToolCall(call, workspaceRoot: workspaceRoot)
        refreshTopBar(agentStatus: result.ok ? TopBarAgentStatusLabel.idle : TopBarAgentStatusLabel.failed)
        return result.ok
    }
}
