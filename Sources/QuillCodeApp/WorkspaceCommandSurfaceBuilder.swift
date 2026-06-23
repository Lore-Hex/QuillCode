import Foundation
import QuillCodeCore
import QuillComputerUseKit

struct WorkspaceCommandSurfaceBuilder: Sendable, Hashable {
    var selectedThread: ChatThread?
    var selectedProject: ProjectRef?
    var selectedSidebarThreads: [ChatThread]
    var sidebarSelectionIsActive: Bool
    var sidebarItemCount: Int
    var hasActiveWorkspaceRoot: Bool
    var canRetryLastUserTurn: Bool
    var composerIsSending: Bool
    var terminalHasEntries: Bool
    var terminalIsRunning: Bool
    var browserCanGoBack: Bool
    var browserCanGoForward: Bool
    var browserCanReload: Bool
    var mcpServerStatuses: [String: MCPServerLifecycleStatus]
    var computerUseStatus: ComputerUseStatus

    var commands: [WorkspaceCommandSurface] {
        threadCommands
            + retryCommand
            + navigationCommands
            + workspaceCommands
            + automationCommands
            + memoryCommands
            + extensionToggleCommands
            + gitCommands
            + localActionCommands
            + mcpLifecycleCommands
            + extensionUpdateCommands
            + controlAndSettingsCommands
            + computerUseCommands
    }

    private var hasSelectedThread: Bool {
        selectedThread != nil
    }

    private var selectedThreadHasMessages: Bool {
        selectedThread?.messages.isEmpty == false
    }

    private var selectedProjectIsRemote: Bool {
        selectedProject?.isRemote == true
    }

    private var hasWorkspaceOrRemoteProject: Bool {
        hasActiveWorkspaceRoot || selectedProjectIsRemote
    }

    private var hasAnySidebarThread: Bool {
        sidebarItemCount > 0
    }

    private var hasSidebarSelection: Bool {
        !selectedSidebarThreads.isEmpty
    }

    private var hasPinnedSidebarSelection: Bool {
        selectedSidebarThreads.contains { $0.isPinned }
    }

    private var hasUnarchivedSidebarSelection: Bool {
        selectedSidebarThreads.contains { !$0.isArchived }
    }

    private var hasArchivedSidebarSelection: Bool {
        selectedSidebarThreads.contains { $0.isArchived }
    }

    private var retryCommand: [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "retry-last-turn",
                title: "Retry last turn",
                category: WorkspaceCommandPalette.controlCategory,
                keywords: ["retry", "rerun", "again", "failed"],
                isEnabled: canRetryLastUserTurn
            )
        ]
    }

    private var threadCommands: [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "new-chat",
                title: "New chat",
                shortcut: WorkspaceShortcutRegistry.label(for: "new-chat"),
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "conversation"]
            ),
            WorkspaceCommandSurface(
                id: "thread-rename",
                title: "Rename chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "title"],
                isEnabled: hasSelectedThread
            ),
            WorkspaceCommandSurface(
                id: "thread-duplicate",
                title: "Duplicate chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "copy"],
                isEnabled: hasSelectedThread
            ),
            WorkspaceCommandSurface(
                id: "thread-archive",
                title: "Archive chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "hide"],
                isEnabled: selectedThread != nil && selectedThread?.isArchived == false
            ),
            WorkspaceCommandSurface(
                id: "thread-unarchive",
                title: "Unarchive chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "restore"],
                isEnabled: selectedThread?.isArchived == true
            ),
            WorkspaceCommandSurface(
                id: "thread-delete",
                title: "Delete chat",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "remove"],
                isEnabled: hasSelectedThread
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .select),
                title: "Select chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "multi"],
                isEnabled: hasAnySidebarThread
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .selectAll),
                title: "Select all chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "all"],
                isEnabled: hasAnySidebarThread
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .clearSelection),
                title: "Clear chat selection",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "done"],
                isEnabled: sidebarSelectionIsActive
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .pin),
                title: "Pin selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "pin"],
                isEnabled: hasUnarchivedSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .unpin),
                title: "Unpin selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "unpin"],
                isEnabled: hasPinnedSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .archive),
                title: "Archive selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "archive"],
                isEnabled: hasUnarchivedSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .unarchive),
                title: "Unarchive selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "restore"],
                isEnabled: hasArchivedSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: SidebarBulkActionSurface.commandID(for: .delete),
                title: "Delete selected chats",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "chat", "bulk", "delete"],
                isEnabled: hasSidebarSelection
            ),
            WorkspaceCommandSurface(
                id: "fork-from-last",
                title: "Fork from last",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "context", "continue"],
                isEnabled: selectedThreadHasMessages
            ),
            WorkspaceCommandSurface(
                id: "compact-context",
                title: "Compact context",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "context", "summarize", "compact"],
                isEnabled: selectedThreadHasMessages
            )
        ]
    }

    private var navigationCommands: [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "search",
                title: "Search",
                shortcut: WorkspaceShortcutRegistry.label(for: "search"),
                category: WorkspaceCommandPalette.navigationCategory,
                keywords: ["find", "threads", "chat"]
            ),
            WorkspaceCommandSurface(
                id: "find-in-chat",
                title: "Find in chat",
                shortcut: WorkspaceShortcutRegistry.label(for: "find-in-chat"),
                category: WorkspaceCommandPalette.navigationCategory,
                keywords: ["find", "current", "transcript", "message"],
                isEnabled: hasSelectedThread
            )
        ]
    }

    private var workspaceCommands: [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "add-project",
                title: "Open project",
                shortcut: WorkspaceShortcutRegistry.label(for: "add-project"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["folder", "workspace", "repo"]
            ),
            WorkspaceCommandSurface(
                id: "add-ssh-project",
                title: "Project: Add SSH Remote...",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["remote", "ssh", "server", "workspace", "/ssh user@host:/path"]
            ),
            WorkspaceCommandSurface(
                id: "project-new-chat",
                title: "New chat in project",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["project", "workspace", "thread", "chat"],
                isEnabled: selectedProject != nil
            ),
            WorkspaceCommandSurface(
                id: "project-refresh-context",
                title: "Refresh project context",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["project", "workspace", "instructions", "memory", "reload"],
                isEnabled: selectedProject != nil
            ),
            WorkspaceCommandSurface(
                id: "project-rename",
                title: "Rename project",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["project", "workspace", "title", "name"],
                isEnabled: selectedProject != nil
            ),
            WorkspaceCommandSurface(
                id: "project-remove",
                title: "Remove project from list",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["project", "workspace", "forget", "remove"],
                isEnabled: selectedProject != nil
            ),
            WorkspaceCommandSurface(
                id: "toggle-terminal",
                title: "Terminal",
                shortcut: WorkspaceShortcutRegistry.label(for: "toggle-terminal"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["shell", "command", "pty"]
            ),
            WorkspaceCommandSurface(
                id: "terminal-clear",
                title: "Terminal: Clear history",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["shell", "command", "clear", "history"],
                isEnabled: terminalHasEntries && !terminalIsRunning
            ),
            WorkspaceCommandSurface(
                id: "toggle-browser",
                title: "Browser",
                shortcut: WorkspaceShortcutRegistry.label(for: "toggle-browser"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "localhost"]
            ),
            WorkspaceCommandSurface(
                id: "browser-back",
                title: "Browser: Back",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "history", "back"],
                isEnabled: browserCanGoBack
            ),
            WorkspaceCommandSurface(
                id: "browser-forward",
                title: "Browser: Forward",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "history", "forward"],
                isEnabled: browserCanGoForward
            ),
            WorkspaceCommandSurface(
                id: "browser-reload",
                title: "Browser: Reload",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "refresh", "reload"],
                isEnabled: browserCanReload
            ),
            WorkspaceCommandSurface(
                id: "toggle-activity",
                title: "Activity",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["task", "summary", "sources", "artifacts", "tools"]
            ),
            WorkspaceCommandSurface(
                id: "toggle-automations",
                title: "Automations",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["automation", "schedule", "recurring", "monitor", "follow-up", "heartbeat"]
            )
        ]
    }

    private var automationCommands: [WorkspaceCommandSurface] {
        [
            .automationCreateThreadFollowUp(isEnabled: hasSelectedThread),
            .automationCreateWorkspaceSchedule(isEnabled: selectedProject != nil)
        ] + WorkspaceCommandSurface.automationScheduleThreadFollowUpCommands(
            isEnabled: hasSelectedThread
        ) + WorkspaceCommandSurface.automationScheduleWorkspaceScheduleCommands(
            isEnabled: selectedProject != nil
        )
    }

    private var memoryCommands: [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "toggle-memories",
                title: "Memories",
                category: WorkspaceCommandPalette.memoriesCategory,
                keywords: ["memory", "context", "preferences", "facts"]
            ),
            WorkspaceCommandSurface(
                id: "memory-add",
                title: "Add memory",
                category: WorkspaceCommandPalette.memoriesCategory,
                keywords: ["remember", "save", "preference", "fact"]
            )
        ]
    }

    private var extensionToggleCommands: [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "toggle-extensions",
                title: "Extensions",
                category: WorkspaceCommandPalette.extensionsCategory,
                keywords: ["plugins", "skills", "mcp", "manifest"],
                isEnabled: hasActiveWorkspaceRoot
            )
        ]
    }

    private var mcpLifecycleCommands: [WorkspaceCommandSurface] {
        (selectedProject?.extensionManifests ?? [])
            .filter { $0.kind == .mcpServer }
            .flatMap { manifest -> [WorkspaceCommandSurface] in
                let status = mcpServerStatuses[manifest.id] ?? .stopped
                let canStart = manifest.isEnabled
                    && manifest.launchExecutable != nil
                    && !status.isActive
                    && hasActiveWorkspaceRoot
                let canStop = status.isActive
                return [
                    WorkspaceCommandSurface(
                        id: "mcp-start:\(manifest.id)",
                        title: "Start \(manifest.name)",
                        category: WorkspaceCommandPalette.extensionsCategory,
                        keywords: ["mcp", "server", "start", "stdio", manifest.name],
                        isEnabled: canStart
                    ),
                    WorkspaceCommandSurface(
                        id: "mcp-stop:\(manifest.id)",
                        title: "Stop \(manifest.name)",
                        category: WorkspaceCommandPalette.extensionsCategory,
                        keywords: ["mcp", "server", "stop", "stdio", manifest.name],
                        isEnabled: canStop
                    )
                ]
            }
    }

    private var extensionUpdateCommands: [WorkspaceCommandSurface] {
        (selectedProject?.extensionManifests ?? [])
            .filter { $0.updateCommand != nil }
            .map { manifest in
                WorkspaceCommandSurface(
                    id: "extension-update:\(manifest.id)",
                    title: "Update \(manifest.name)",
                    category: WorkspaceCommandPalette.extensionsCategory,
                    keywords: [
                        "extension",
                        "plugin",
                        "skill",
                        "mcp",
                        "update",
                        manifest.kind.title,
                        manifest.name,
                        manifest.version ?? "",
                        manifest.sourceURL ?? ""
                    ].filter { !$0.isEmpty },
                    isEnabled: hasActiveWorkspaceRoot
                )
            }
    }

    private var gitCommands: [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "git-status",
                title: "Git status",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "status", "changes", "remote"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-diff",
                title: "Review diff",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "diff", "review", "changes", "remote"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-create",
                title: "Create pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "pull request", "review"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-view",
                title: "View pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "view", "comments", "review"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-checks",
                title: "Pull request checks",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "checks", "ci", "status"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-diff",
                title: "Pull request diff",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "pr diff", "pull request diff", "diff", "review", "changes"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-checkout",
                title: "Checkout pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "checkout", "switch", "branch"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-reviewers",
                title: "Request pull request reviewers",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "reviewer", "reviewers", "request review"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-comment",
                title: "Comment on pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "comment", "comment pull", "reply", "discussion"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-review",
                title: "Review pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "review", "approve", "approve pr", "request changes"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-labels",
                title: "Label pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "label", "labels", "triage"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-merge",
                title: "Merge pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "merge", "automerge", "merge train"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-list",
                title: "List worktrees",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-create",
                title: "Create worktree",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-remove",
                title: "Remove worktree",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace", "delete"],
                isEnabled: hasWorkspaceOrRemoteProject
            )
        ]
    }

    private var localActionCommands: [WorkspaceCommandSurface] {
        (selectedProject?.localActions ?? []).map { action in
            WorkspaceCommandSurface(
                id: action.id,
                title: "Run \(action.title)",
                category: WorkspaceCommandPalette.environmentCategory,
                keywords: keywords(for: action),
                isEnabled: hasActiveWorkspaceRoot
            )
        }
    }

    private func keywords(for action: LocalEnvironmentAction) -> [String] {
        let baseKeywords = [
            "local environment",
            "script"
        ] + [action.detail].compactMap { $0 } + [
            "bootstrap",
            action.title,
            action.relativePath
        ]
        let workingDirectoryKeywords = [action.workingDirectory].compactMap { $0 }
        let timeoutKeywords = action.timeoutSeconds.map { ["timeout", "\($0)s"] } ?? []
        let environmentKeywords = action.environment?.keys.sorted() ?? []
        return baseKeywords + workingDirectoryKeywords + timeoutKeywords + environmentKeywords
    }

    private var controlAndSettingsCommands: [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "stop-all",
                title: "Stop all",
                shortcut: WorkspaceShortcutRegistry.label(for: "stop-all"),
                category: WorkspaceCommandPalette.controlCategory,
                keywords: ["cancel", "abort", "halt"],
                isEnabled: composerIsSending
                    || terminalIsRunning
                    || mcpServerStatuses.values.contains { $0.isActive }
            ),
            WorkspaceCommandSurface(
                id: "settings",
                title: "Settings",
                shortcut: WorkspaceShortcutRegistry.label(for: "settings"),
                category: WorkspaceCommandPalette.navigationCategory,
                keywords: ["preferences", "trustedrouter", "auth"]
            ),
            WorkspaceCommandSurface(
                id: "command-palette",
                title: "Command palette",
                shortcut: WorkspaceShortcutRegistry.label(for: "command-palette"),
                category: WorkspaceCommandPalette.navigationCategory,
                keywords: ["commands", "actions"]
            ),
            WorkspaceCommandSurface(
                id: "keyboard-shortcuts",
                title: "Keyboard shortcuts",
                shortcut: WorkspaceShortcutRegistry.label(for: "keyboard-shortcuts"),
                category: WorkspaceCommandPalette.navigationCategory,
                keywords: ["keyboard", "shortcuts", "help", "commands"]
            )
        ]
    }

    private var computerUseCommands: [WorkspaceCommandSurface] {
        [
            .computerUseSetup(isEnabled: !computerUseStatus.available),
            .computerUseScreenRecordingSettings(isEnabled: !computerUseStatus.screenRecordingGranted),
            .computerUseAccessibilitySettings(isEnabled: !computerUseStatus.accessibilityGranted),
            .computerUseRefresh
        ]
    }
}
