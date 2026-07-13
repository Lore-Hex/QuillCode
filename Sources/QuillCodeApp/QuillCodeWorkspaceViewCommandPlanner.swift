import Foundation

enum WorkspaceViewCommandAction: Hashable, Sendable {
    case presentSettings
    case presentSearch
    case presentFind
    case requestAddProject
    case presentCommandPalette
    case presentKeyboardShortcuts
    case presentSidebarSavedSearch
    case renameThread(threadID: UUID, title: String)
    case renameProject(projectID: UUID, name: String)
    case presentNewWorktreeTask
    case presentCreateWorktree
    case presentCreateWorktreeBranch
    case presentOpenWorktree
    case presentRemoveWorktree
    case presentPruneWorktrees
    case openBrowserSession
    case copyConversation
    case exportConversationMarkdown
    case dispatch(command: WorkspaceCommandSurface, focusesComposer: Bool)
}

struct WorkspaceViewCommandPlanner: Sendable, Hashable {
    var sidebar: SidebarSurface
    var projects: ProjectListSurface

    func action(for command: WorkspaceCommandSurface) -> WorkspaceViewCommandAction? {
        switch command.id {
        case "settings", "computer-use-setup":
            return .presentSettings
        case "search":
            return .presentSearch
        case "find-in-chat":
            return .presentFind
        case "add-project":
            return .requestAddProject
        case "command-palette":
            return .presentCommandPalette
        case "keyboard-shortcuts":
            return .presentKeyboardShortcuts
        case "sidebar-saved-search-create":
            return .presentSidebarSavedSearch
        case "thread-rename":
            return selectedThreadRenameAction()
        case "project-rename":
            return selectedProjectRenameAction()
        case "thread-new-worktree":
            return .presentNewWorktreeTask
        case "git-worktree-create":
            return .presentCreateWorktree
        case "thread-create-branch":
            return .presentCreateWorktreeBranch
        case "git-worktree-open":
            return .presentOpenWorktree
        case "git-worktree-remove":
            return .presentRemoveWorktree
        case "git-worktree-prune":
            return .presentPruneWorktrees
        case "open-browser-session":
            return .openBrowserSession
        case "copy-conversation":
            return .copyConversation
        case "export-conversation-markdown":
            return .exportConversationMarkdown
        default:
            guard WorkspaceCommandRoutingCatalog.isDispatchable(command.id) else {
                return nil
            }
            return .dispatch(
                command: command,
                focusesComposer: shouldFocusComposer(afterDispatching: command)
            )
        }
    }

    private func selectedThreadRenameAction() -> WorkspaceViewCommandAction? {
        guard let selectedID = sidebar.selectedThreadID,
              let item = sidebar.items.first(where: { $0.id == selectedID })
        else {
            return nil
        }
        return .renameThread(threadID: item.id, title: item.title)
    }

    private func selectedProjectRenameAction() -> WorkspaceViewCommandAction? {
        guard let selectedID = projects.selectedProjectID,
              let item = projects.items.first(where: { $0.id == selectedID })
        else {
            return nil
        }
        return .renameProject(projectID: item.id, name: item.name)
    }

    private func shouldFocusComposer(afterDispatching command: WorkspaceCommandSurface) -> Bool {
        SlashCommandCatalog.insertText(forCommandPaletteID: command.id) != nil
            || command.id == "memory-add"
            || command.id == "add-ssh-project"
            || command.id == "project-rename"
            || command.id == "thread-rename"
    }
}
