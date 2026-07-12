import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public var selectedThread: ChatThread? {
        guard let selectedThreadID = root.selectedThreadID else { return nil }
        return root.threads.first { $0.id == selectedThreadID }
    }

    public var selectedProject: ProjectRef? {
        guard let selectedProjectID = root.selectedProjectID else { return nil }
        return root.projects.first { $0.id == selectedProjectID }
    }

    public var activeWorkspaceRoot: URL? {
        workspaceRoot(forThreadID: root.selectedThreadID)
    }

    /// Resolves the local execution root for one chat without consulting current UI selection.
    /// Background runs use this to remain pinned to their project/worktree while another chat is open.
    public func workspaceRoot(forThreadID threadID: UUID?) -> URL? {
        let thread = threadID.flatMap { id in root.threads.first { $0.id == id } }
        let projectID = thread?.projectID ?? (threadID == root.selectedThreadID ? root.selectedProjectID : nil)
        guard let projectID,
              let project = root.projects.first(where: { $0.id == projectID }),
              !project.isRemote
        else { return nil }
        // A thread bound to a worktree runs in that isolated directory instead of the shared project
        // root, so two threads on the same project don't clobber each other. A dangling binding falls
        // back to the project root rather than pointing at a missing directory.
        if let worktree = thread?.worktree, worktree.isResolvable {
            return URL(fileURLWithPath: worktree.path)
        }
        return URL(fileURLWithPath: project.path)
    }

    var terminalCurrentDirectoryURL: URL? {
        WorkspaceTerminalEngine.currentDirectoryURL(
            terminal: terminal,
            selectedProjectID: knownProjectID(root.selectedProjectID),
            selectedProjectIsRemote: selectedProject?.isRemote == true,
            activeWorkspaceRoot: activeWorkspaceRoot
        )
    }

    public var currentToolCards: [ToolCardState] {
        guard let selectedThread else { return [] }
        let cards = WorkspaceTranscriptSurfaceBuilder(thread: selectedThread).toolCards()
        return executionContextSurfaceBuilder.enrichToolCards(cards, for: selectedThread)
    }

    public var currentTimelineItems: [TranscriptTimelineItemSurface] {
        guard let selectedThread else { return [] }
        let items = WorkspaceTranscriptSurfaceBuilder(thread: selectedThread, allowsRevert: selectedProject?.isRemote != true).timelineItems()
        return executionContextSurfaceBuilder.enrichTimelineItems(items, for: selectedThread)
    }

    private var executionContextSurfaceBuilder: WorkspaceExecutionContextSurfaceBuilder {
        WorkspaceExecutionContextSurfaceBuilder(
            selectedProject: selectedProject,
            projects: root.projects
        )
    }

    func project(id: UUID) -> ProjectRef? {
        root.projects.first { $0.id == id }
    }
}
