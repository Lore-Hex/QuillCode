import Foundation

struct WorkspaceThreadCommandAvailability: Sendable, Hashable {
    var hasSelectedThread: Bool
    var selectedThreadIsArchived: Bool
    var selectedThreadIsEphemeral: Bool = false
    /// True only for side conversations (which have a parent to return to) — NOT for confidential,
    /// which is also ephemeral but has nowhere to "return"; keying return-affordances off generic
    /// ephemerality would surface a silently-no-op command inside confidential chats.
    var selectedThreadIsSideConversation: Bool = false
    var selectedThreadHasMessages: Bool
    var selectedThreadCanClear: Bool
    var selectedThreadCanRevertLatestTurn: Bool
    var selectedThreadCanPin: Bool
    var selectedThreadCanUnpin: Bool
    var selectedThreadIsRunning: Bool = false
    var selectedThreadCanRestoreWorktree: Bool = false
    var selectedThreadHandoffTitle: String? = nil
    var selectedThreadFinishWorktreeTitle: String? = nil
    var selectedThreadCanCreateBranch: Bool = false
    var selectedThreadCanPublishBranch: Bool = false
    var selectedThreadCanRefreshPullRequest: Bool = false
    var selectedThreadCanLandPullRequest: Bool = false
    var selectedThreadCanCleanupMergedWorktree: Bool = false
    var hasAnySidebarThread: Bool
    var sidebarSelectionIsActive: Bool
    var hasSidebarSelection: Bool
    var hasPinnedSidebarSelection: Bool
    var hasUnpinnedUnarchivedSidebarSelection: Bool
    var hasUnarchivedSidebarSelection: Bool
    var hasArchivedSidebarSelection: Bool
    var hasRunningSidebarSelection: Bool = false

    var selectedThreadCanArchive: Bool {
        hasSelectedThread && !selectedThreadIsArchived && !selectedThreadIsEphemeral
    }
}

enum WorkspaceThreadCommandCatalog {
    static func commands(
        availability: WorkspaceThreadCommandAvailability,
        savedSearches: [SidebarSavedSearch] = []
    ) -> [WorkspaceCommandSurface] {
        sideConversationCommands(availability: availability) + [
            WorkspaceCommandSurface(
                id: "new-chat",
                title: "New chat",
                shortcut: WorkspaceShortcutRegistry.label(for: "new-chat"),
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "conversation"]
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.newConfidentialChat.rawValue,
                title: "New confidential chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "conversation", "confidential", "private", "ephemeral", "e2e", "encrypted", "not saved"]
            ),
            WorkspaceCommandSurface(
                id: "thread-new-worktree",
                title: "New worktree task",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "worktree", "branch", "isolated", "fork", "parallel"]
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.threadRestoreWorktree.rawValue,
                title: "Restore worktree",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "task", "worktree", "snapshot", "restore", "archive"],
                isEnabled: availability.selectedThreadCanRestoreWorktree
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.threadCreateBranch.rawValue,
                title: "Create branch here",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "task", "worktree", "branch", "permanent", "detached"],
                isEnabled: availability.selectedThreadCanCreateBranch
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.threadPublishBranch.rawValue,
                title: "Publish branch",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "task", "worktree", "branch", "push", "publish", "pull request", "pr"],
                isEnabled: availability.selectedThreadCanPublishBranch
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.threadRefreshPullRequest.rawValue,
                title: "Refresh pull request",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "task", "pull request", "pr", "github", "refresh", "status"],
                isEnabled: availability.selectedThreadCanRefreshPullRequest
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.threadLandPullRequest.rawValue,
                title: "Land pull request",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "task", "pull request", "pr", "github", "merge", "queue", "land"],
                isEnabled: availability.selectedThreadCanLandPullRequest
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.threadCleanupMergedWorktree.rawValue,
                title: "Clean up merged worktree",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "task", "pull request", "pr", "merged", "worktree", "cleanup", "remove"],
                isEnabled: availability.selectedThreadCanCleanupMergedWorktree
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.threadHandoff.rawValue,
                title: availability.selectedThreadHandoffTitle ?? "Hand off task",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "task", "handoff", "local", "worktree", "move", "transfer"],
                isEnabled: availability.selectedThreadHandoffTitle != nil
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.threadFinishWorktree.rawValue,
                title: availability.selectedThreadFinishWorktreeTitle ?? "Finish task in Local",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "task", "finish", "land", "local", "worktree", "cleanup"],
                isEnabled: availability.selectedThreadFinishWorktreeTitle != nil
            ),
            savedFilterCommand(.all),
            savedFilterCommand(.pinned),
            savedFilterCommand(.recent),
            savedFilterCommand(.archived),
            WorkspaceCommandSurface(
                id: "thread-rename",
                title: "Rename chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "title"],
                isEnabled: availability.hasSelectedThread && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: "thread-duplicate",
                title: "Duplicate chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "copy"],
                isEnabled: availability.hasSelectedThread
                    && !availability.selectedThreadIsRunning
                    && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: "thread-pin",
                title: "Pin chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "pin", "pinned"],
                isEnabled: availability.selectedThreadCanPin && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: "thread-unpin",
                title: "Unpin chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "pin", "unpin", "pinned"],
                isEnabled: availability.selectedThreadCanUnpin && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: "thread-clear",
                title: "Clear chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "reset", "context", "transcript"],
                isEnabled: availability.selectedThreadCanClear && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: "thread-revert-latest",
                title: "Undo latest edit",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "undo", "revert", "latest", "edit"],
                isEnabled: availability.selectedThreadCanRevertLatestTurn && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: "thread-archive",
                title: "Archive chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "hide"],
                isEnabled: availability.selectedThreadCanArchive
            ),
            WorkspaceCommandSurface(
                id: "thread-unarchive",
                title: "Unarchive chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "restore"],
                isEnabled: availability.selectedThreadIsArchived && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: "thread-delete",
                title: "Delete chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "remove"],
                isEnabled: availability.hasSelectedThread
                    && !availability.selectedThreadIsRunning
                    && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .select),
                title: "Select chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "multi"],
                isEnabled: availability.hasAnySidebarThread
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .selectAll),
                title: "Select all chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "all"],
                isEnabled: availability.hasAnySidebarThread
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .clearSelection),
                title: "Clear chat selection",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "done"],
                isEnabled: availability.sidebarSelectionIsActive
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .pin),
                title: "Pin selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "pin"],
                isEnabled: availability.hasUnpinnedUnarchivedSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .unpin),
                title: "Unpin selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "unpin"],
                isEnabled: availability.hasPinnedSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .archive),
                title: "Archive selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "archive"],
                isEnabled: availability.hasUnarchivedSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .unarchive),
                title: "Unarchive selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "restore"],
                isEnabled: availability.hasArchivedSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .delete),
                title: "Delete selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "delete"],
                isEnabled: availability.hasSidebarSelection && !availability.hasRunningSidebarSelection
            ),
            WorkspaceThreadForkStrategy.latestTurn.command(
                isEnabled: availability.selectedThreadHasMessages && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceThreadForkStrategy.summarizedContext.command(
                isEnabled: availability.selectedThreadHasMessages && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceThreadForkStrategy.fullContext.command(
                isEnabled: availability.selectedThreadHasMessages && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: "compact-context",
                title: "Compact context",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "context", "summarize", "compact"],
                isEnabled: availability.selectedThreadHasMessages && !availability.selectedThreadIsEphemeral
            ),
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.sidebarSavedSearchCreate.rawValue,
                title: "Create sidebar search",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "sidebar", "filter"]
            )
        ] + savedSearchCommands(savedSearches)
    }

    private static func sideConversationCommands(
        availability: WorkspaceThreadCommandAvailability
    ) -> [WorkspaceCommandSurface] {
        guard availability.selectedThreadIsSideConversation else { return [] }
        return [
            WorkspaceCommandSurface(
                id: WorkspaceCommandAction.sideConversationReturn.rawValue,
                title: "Return to main chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["side", "conversation", "return", "back", "btw"]
            )
        ]
    }

    private static func savedFilterCommand(_ filter: SidebarSavedFilterKind) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: filter.commandID,
            title: "Show \(filter.title.lowercased()) chats",
            category: WorkspaceCommandPalette.threadCategory,
            keywords: ["thread", "chat", "sidebar", "filter", filter.title.lowercased()]
        )
    }

    private static func savedSearchCommands(_ savedSearches: [SidebarSavedSearch]) -> [WorkspaceCommandSurface] {
        let validSavedSearches = savedSearches.filter(\.isValid)
        return validSavedSearches.enumerated().flatMap { index, savedSearch in
            [
                WorkspaceCommandSurface(
                    id: SidebarSavedSearchSurface.commandID(for: savedSearch.id),
                    title: "Show \(savedSearch.title)",
                    category: WorkspaceCommandPalette.threadCategory,
                    keywords: ["thread", "chat", "sidebar", "saved search", "search", savedSearch.query]
                ),
                WorkspaceCommandSurface(
                    id: SidebarSavedSearchSurface.moveCommandID(for: savedSearch.id, direction: .up),
                    title: "Move saved search \(savedSearch.title) up",
                    category: WorkspaceCommandPalette.threadCategory,
                    keywords: ["thread", "chat", "sidebar", "saved search", "move", "up", savedSearch.query],
                    isEnabled: index > 0
                ),
                WorkspaceCommandSurface(
                    id: SidebarSavedSearchSurface.moveCommandID(for: savedSearch.id, direction: .down),
                    title: "Move saved search \(savedSearch.title) down",
                    category: WorkspaceCommandPalette.threadCategory,
                    keywords: ["thread", "chat", "sidebar", "saved search", "move", "down", savedSearch.query],
                    isEnabled: index < validSavedSearches.count - 1
                ),
                WorkspaceCommandSurface(
                    id: SidebarSavedSearchSurface.deleteCommandID(for: savedSearch.id),
                    title: "Delete saved search \(savedSearch.title)",
                    category: WorkspaceCommandPalette.threadCategory,
                    keywords: ["thread", "chat", "sidebar", "saved search", "delete", savedSearch.query]
                )
            ]
        }
    }
}
