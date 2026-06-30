import Foundation
import QuillCodeCore

enum WorkspaceCommandActionEffect: Sendable, Hashable {
    case newChat
    case cycleMode
    case focusComposer
    case toggleTerminal
    case clearTerminal
    case toggleBrowser
    case browserBack
    case browserForward
    case browserReload
    case toggleExtensions
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
    case setDraft(String)
    case removeProject(projectID: UUID)
    case duplicateThread(threadID: UUID)
    case archiveThread(threadID: UUID)
    case unarchiveThread(threadID: UUID)
    case deleteThread(threadID: UUID)
    case sidebarBulkAction(SidebarBulkActionKind)
    case retryLastTurn
    case forkThread(WorkspaceThreadForkStrategy)
    case compactContext
    case disconnectAll
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
        case .cycleMode:
            return .cycleMode
        case .focusComposer:
            return .focusComposer
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
        case .projectRename:
            return selectedProject.map { .setDraft("/project rename \($0.name)") }
        case .projectRemove:
            return selectedProjectID.map { .removeProject(projectID: $0) }
        case .threadRename:
            return selectedThread.map { .setDraft("/rename \($0.title)") }
        case .threadDuplicate:
            return selectedThreadID.map { .duplicateThread(threadID: $0) }
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
        }
    }
}
