import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceExecutionContextSurfaceBuilder: Sendable, Hashable {
    var selectedProject: ProjectRef?
    var projects: [ProjectRef]

    func enrichToolCards(_ cards: [ToolCardState], for thread: ChatThread) -> [ToolCardState] {
        guard let context = context(for: thread) else { return cards }
        return cards.map { card in
            guard card.executionContext == nil,
                  Self.isProjectExecutionTool(card.title)
            else {
                return card
            }
            var copy = card
            copy.executionContext = context
            return copy
        }
    }

    func enrichTimelineItems(
        _ items: [TranscriptTimelineItemSurface],
        for thread: ChatThread
    ) -> [TranscriptTimelineItemSurface] {
        guard let context = context(for: thread) else { return items }
        return items.map { item in
            guard var card = item.toolCard,
                  card.executionContext == nil,
                  Self.isProjectExecutionTool(card.title)
            else {
                return item
            }
            card.executionContext = context
            return .toolCard(card)
        }
    }

    func context(for thread: ChatThread) -> ExecutionContextSurface? {
        let resolvedProject: ProjectRef?
        if let projectID = thread.projectID {
            resolvedProject = project(id: projectID) ?? selectedProject
        } else {
            resolvedProject = selectedProject
        }
        guard let resolvedProject else { return nil }
        return .project(resolvedProject)
    }

    static func isProjectExecutionTool(_ toolName: String) -> Bool {
        projectExecutionToolNames.contains(toolName)
    }

    private func project(id: UUID) -> ProjectRef? {
        projects.first { $0.id == id }
    }

    private static let projectExecutionToolNames: Set<String> = [
        ToolDefinition.shellRun.name,
        ToolDefinition.fileRead.name,
        ToolDefinition.fileWrite.name,
        ToolDefinition.applyPatch.name,
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
        ToolDefinition.gitStage.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitStageHunk.name,
        ToolDefinition.gitRestoreHunk.name,
        ToolDefinition.gitCommit.name,
        ToolDefinition.gitPush.name,
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestMerge.name,
        ToolDefinition.gitWorktreeList.name,
        ToolDefinition.gitWorktreeCreate.name,
        ToolDefinition.gitWorktreeOpen.name,
        ToolDefinition.gitWorktreeRemove.name,
        ToolDefinition.gitWorktreePrune.name
    ]
}
