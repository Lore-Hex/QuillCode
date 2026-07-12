import Foundation
import QuillCodeCore

enum WorkspaceCommandActionEffect: Sendable, Hashable {
    case newChat
    case workspaceBack
    case workspaceForward
    case cycleMode
    case focusComposer
    case toggleSidebar
    case toggleTerminal
    case clearTerminal
    case toggleBrowser
    case browserBack
    case browserForward
    case browserReload
    case toggleExtensions
    case showSkills
    case toggleMemories
    case toggleActivity
    case toggleAutomations
    case openPullRequestReviewDraft
    case createThreadFollowUp
    case createWorkspaceSchedule
    case createThreadFollowUpTomorrow
    case createWorkspaceScheduleTomorrow
    case newProjectThread(projectID: UUID)
    case refreshProjectContext(projectID: UUID)
    case initProject(projectID: UUID)
    case moveProjectToTop(projectID: UUID)
    case moveProjectToBottom(projectID: UUID)
    case moveProject(projectID: UUID, direction: WorkspaceProjectMoveDirection)
    case setDraft(String)
    case removeProject(projectID: UUID)
    case duplicateThread(threadID: UUID)
    case newWorktreeThread
    case handoffSelectedThread
    case setThreadPinned(threadID: UUID, isPinned: Bool)
    case clearThread(threadID: UUID)
    case revertLatestTurn
    case archiveThread(threadID: UUID)
    case unarchiveThread(threadID: UUID)
    case deleteThread(threadID: UUID)
    case sidebarBulkAction(SidebarBulkActionKind)
    case retryLastTurn
    case forkThread(WorkspaceThreadForkStrategy)
    case compactContext
    case disconnectAll
    case attentionNext
    case attentionPrevious
    case attentionOpen
    case attentionAcknowledge
    case attentionDismiss
}

struct WorkspaceCommandActionPlanner: Sendable, Hashable {
    var selectedProjectID: UUID?
    var selectedProject: ProjectRef?
    var selectedThreadID: UUID?
    var selectedThread: ChatThread?

    func effect(for action: WorkspaceCommandAction) -> WorkspaceCommandActionEffect? {
        switch action {
        case .newChat:
            return .newChat
        case .workspaceBack:
            return .workspaceBack
        case .workspaceForward:
            return .workspaceForward
        case .cycleMode:
            return .cycleMode
        case .focusComposer:
            return .focusComposer
        case .toggleSidebar:
            return .toggleSidebar
        case .toggleTerminal:
            return .toggleTerminal
        case .clearTerminal:
            return .clearTerminal
        case .toggleBrowser:
            return .toggleBrowser
        case .browserBack:
            return .browserBack
        case .browserForward:
            return .browserForward
        case .browserReload:
            return .browserReload
        case .toggleExtensions:
            return .toggleExtensions
        case .showSkills:
            return .showSkills
        case .toggleMemories:
            return .toggleMemories
        case .toggleActivity:
            return .toggleActivity
        case .toggleAutomations:
            return .toggleAutomations
        case .pullRequestReviewDraft:
            return .openPullRequestReviewDraft
        case .createThreadFollowUp:
            return .createThreadFollowUp
        case .createWorkspaceSchedule:
            return .createWorkspaceSchedule
        case .createThreadFollowUpTomorrow:
            return .createThreadFollowUpTomorrow
        case .createWorkspaceScheduleTomorrow:
            return .createWorkspaceScheduleTomorrow
        case .projectNewChat:
            return selectedProjectID.map { .newProjectThread(projectID: $0) }
        case .projectRefreshContext:
            return selectedProjectID.map { .refreshProjectContext(projectID: $0) }
        case .projectInit:
            return selectedProjectID.map { .initProject(projectID: $0) }
        case .projectMoveToTop:
            return selectedProjectID.map { .moveProjectToTop(projectID: $0) }
        case .projectMoveUp:
            return selectedProjectID.map { .moveProject(projectID: $0, direction: .up) }
        case .projectMoveDown:
            return selectedProjectID.map { .moveProject(projectID: $0, direction: .down) }
        case .projectMoveToBottom:
            return selectedProjectID.map { .moveProjectToBottom(projectID: $0) }
        case .projectRename:
            return selectedProject.map { .setDraft("/project rename \($0.name)") }
        case .projectRemove:
            return selectedProjectID.map { .removeProject(projectID: $0) }
        case .threadRename:
            return selectedThread.map { .setDraft("/rename \($0.title)") }
        case .threadDuplicate:
            return selectedThreadID.map { .duplicateThread(threadID: $0) }
        case .threadNewWorktree:
            return .newWorktreeThread
        case .threadHandoff:
            return .handoffSelectedThread
        case .threadCreateBranch:
            return .setDraft("/branch create ")
        case .threadPin:
            guard let selectedThreadID,
                  let selectedThread,
                  !selectedThread.isPinned,
                  !selectedThread.isArchived
            else { return nil }
            return .setThreadPinned(threadID: selectedThreadID, isPinned: true)
        case .threadUnpin:
            guard let selectedThreadID,
                  selectedThread?.isPinned == true
            else { return nil }
            return .setThreadPinned(threadID: selectedThreadID, isPinned: false)
        case .threadClear:
            return selectedThreadID.map { .clearThread(threadID: $0) }
        case .threadRevertLatest:
            guard selectedProject?.isRemote != true,
                  let selectedThread,
                  WorkspaceTurnRevertPlanner.latestPlan(in: selectedThread) != nil
            else { return nil }
            return .revertLatestTurn
        case .threadArchive:
            return selectedThreadID.map { .archiveThread(threadID: $0) }
        case .threadUnarchive:
            return selectedThreadID.map { .unarchiveThread(threadID: $0) }
        case .threadDelete:
            return selectedThreadID.map { .deleteThread(threadID: $0) }
        case .threadSelectionStart:
            return .sidebarBulkAction(.select)
        case .threadSelectionSelectAll:
            return .sidebarBulkAction(.selectAll)
        case .threadSelectionClear:
            return .sidebarBulkAction(.clearSelection)
        case .threadBulkPin:
            return .sidebarBulkAction(.pin)
        case .threadBulkUnpin:
            return .sidebarBulkAction(.unpin)
        case .threadBulkArchive:
            return .sidebarBulkAction(.archive)
        case .threadBulkUnarchive:
            return .sidebarBulkAction(.unarchive)
        case .threadBulkDelete:
            return .sidebarBulkAction(.delete)
        case .sidebarSavedSearchCreate:
            return nil
        case .retryLastTurn:
            return .retryLastTurn
        case .forkFromLast:
            return .forkThread(.latestTurn)
        case .forkWithSummary:
            return .forkThread(.summarizedContext)
        case .forkFullContext:
            return .forkThread(.fullContext)
        case .compactContext:
            return .compactContext
        case .disconnectAll:
            return .disconnectAll
        case .attentionNext:
            return .attentionNext
        case .attentionPrevious:
            return .attentionPrevious
        case .attentionOpen:
            return .attentionOpen
        case .attentionAcknowledge:
            return .attentionAcknowledge
        case .attentionDismiss:
            return .attentionDismiss
        }
    }
}
