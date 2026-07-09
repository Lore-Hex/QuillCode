import Foundation
import QuillComputerUseKit

enum WorkspaceCommandStaticCatalog {
    typealias Command = WorkspaceCommandSurface

    static func retryCommands(canRetryLastUserTurn: Bool) -> [Command] {
        let control = Category.control
        return [
            shortcut(
                "retry-last-turn",
                "Retry last turn",
                category: control,
                keywords: ["retry", "rerun", "again", "failed"],
                isEnabled: canRetryLastUserTurn
            )
        ]
    }

    static func navigationCommands(
        hasSelectedThread: Bool,
        canNavigateBack: Bool,
        canNavigateForward: Bool
    ) -> [Command] {
        let navigation = Category.navigation
        return [
            shortcut(
                "workspace-back",
                "Back",
                category: navigation,
                keywords: ["history", "previous", "navigation", "thread", "project"],
                isEnabled: canNavigateBack
            ),
            shortcut(
                "workspace-forward",
                "Forward",
                category: navigation,
                keywords: ["history", "next", "navigation", "thread", "project"],
                isEnabled: canNavigateForward
            ),
            shortcut(
                "search",
                "Search",
                category: navigation,
                keywords: ["find", "threads", "chat"]
            ),
            shortcut(
                "find-in-chat",
                "Find in chat",
                category: navigation,
                keywords: ["find", "current", "transcript", "message"],
                isEnabled: hasSelectedThread
            ),
            shortcut(
                "copy-conversation",
                "Copy conversation",
                category: navigation,
                keywords: ["export", "transcript", "markdown", "copy all", "share"],
                isEnabled: hasSelectedThread
            ),
            command(
                "export-conversation-markdown",
                "Export conversation as Markdown...",
                category: navigation,
                keywords: ["export", "transcript", "markdown", "file", "save", "share"],
                isEnabled: hasSelectedThread
            )
        ]
    }

    static func workspaceCommands(
        hasSelectedProject: Bool,
        terminalHasEntries: Bool,
        terminalIsRunning: Bool,
        browserCanGoBack: Bool,
        browserCanGoForward: Bool,
        browserCanReload: Bool,
        browserCanOpenSession: Bool
    ) -> [Command] {
        let navigation = Category.navigation
        return [
            shortcut(
                "cycle-mode",
                "Cycle approval mode",
                keywords: ["mode", "approval", "auto", "plan", "review", "read-only", "safety", "cycle"]
            ),
            shortcut(
                "focus-composer",
                "Focus message input",
                keywords: ["focus", "composer", "message", "input", "prompt", "type"]
            ),
            shortcut(
                "toggle-sidebar",
                "Toggle sidebar",
                category: navigation,
                keywords: ["sidebar", "navigation", "hide", "show", "chats", "projects"]
            ),
            shortcut(
                "add-project",
                "Open project",
                keywords: ["folder", "workspace", "repo"]
            ),
            command(
                "add-ssh-project",
                "Project: Add SSH Remote...",
                keywords: ["remote", "ssh", "server", "workspace", "/ssh user@host:/path"]
            ),
            command(
                "project-new-chat",
                "New chat in project",
                keywords: ["project", "workspace", "thread", "chat"],
                isEnabled: hasSelectedProject
            ),
            command(
                "project-refresh-context",
                "Refresh project context",
                keywords: ["project", "workspace", "instructions", "memory", "reload"],
                isEnabled: hasSelectedProject
            ),
            command(
                "project-init",
                "Initialize AGENTS.md",
                keywords: ["init", "agents", "scaffold", "instructions", "rules", "generate"],
                isEnabled: hasSelectedProject
            ),
            command(
                "project-move-to-top",
                "Project: Move to top",
                keywords: ["project", "workspace", "sidebar", "reorder", "top", "pin"],
                isEnabled: hasSelectedProject
            ),
            command(
                "project-move-up",
                "Project: Move up",
                keywords: ["project", "workspace", "sidebar", "reorder", "up"],
                isEnabled: hasSelectedProject
            ),
            command(
                "project-move-down",
                "Project: Move down",
                keywords: ["project", "workspace", "sidebar", "reorder", "down"],
                isEnabled: hasSelectedProject
            ),
            command(
                "project-rename",
                "Rename project",
                keywords: ["project", "workspace", "title", "name"],
                isEnabled: hasSelectedProject
            ),
            command(
                "project-remove",
                "Remove project from list",
                keywords: ["project", "workspace", "forget", "remove"],
                isEnabled: hasSelectedProject
            ),
            shortcut(
                "toggle-terminal",
                "Terminal",
                keywords: ["shell", "command", "pty"]
            ),
            command(
                "terminal-clear",
                "Terminal: Clear history",
                keywords: ["shell", "command", "clear", "history"],
                isEnabled: terminalHasEntries && !terminalIsRunning
            ),
            shortcut(
                "toggle-browser",
                "Browser",
                keywords: ["preview", "web", "localhost"]
            ),
            shortcut(
                "browser-back",
                "Browser: Back",
                keywords: ["preview", "web", "history", "back"],
                isEnabled: browserCanGoBack
            ),
            shortcut(
                "browser-forward",
                "Browser: Forward",
                keywords: ["preview", "web", "history", "forward"],
                isEnabled: browserCanGoForward
            ),
            shortcut(
                "browser-reload",
                "Browser: Reload",
                keywords: ["preview", "web", "refresh", "reload"],
                isEnabled: browserCanReload
            ),
            command(
                "open-browser-session",
                "Browser: Open session",
                keywords: ["preview", "web", "session", "login", "cookies", "sign in"],
                isEnabled: browserCanOpenSession
            ),
            shortcut(
                "toggle-activity",
                "Activity",
                keywords: ["task", "summary", "sources", "artifacts", "tools"]
            ),
            shortcut(
                "toggle-automations",
                "Automations",
                keywords: ["automation", "schedule", "recurring", "monitor", "follow-up", "heartbeat"]
            )
        ]
    }

    static func automationCommands(
        hasSelectedThread: Bool,
        hasSelectedProject: Bool
    ) -> [Command] {
        [
            .automationCreateThreadFollowUp(isEnabled: hasSelectedThread),
            .automationCreateWorkspaceSchedule(isEnabled: hasSelectedProject),
            .automationCreateMonitor(isEnabled: true)
        ] + Command.automationScheduleThreadFollowUpCommands(
            isEnabled: hasSelectedThread
        ) + Command.automationScheduleWorkspaceScheduleCommands(
            isEnabled: hasSelectedProject
        )
    }

    static func memoryCommands() -> [Command] {
        let memories = Category.memories
        return [
            shortcut(
                "toggle-memories",
                "Memories",
                category: memories,
                keywords: ["memory", "context", "preferences", "facts"]
            ),
            command(
                "memory-add",
                "Add memory",
                category: memories,
                keywords: ["remember", "save", "preference", "fact"]
            )
        ]
    }

    static func extensionToggleCommands(hasActiveWorkspaceRoot: Bool) -> [Command] {
        [
            shortcut(
                "toggle-extensions",
                "Extensions",
                category: Category.extensions,
                keywords: ["plugins", "skills", "mcp", "manifest"],
                isEnabled: hasActiveWorkspaceRoot
            )
        ]
    }

    static func controlAndSettingsCommands(
        composerIsSending: Bool,
        terminalIsRunning: Bool,
        hasActiveMCPServer: Bool,
        hasSelectedRemoteProject: Bool
    ) -> [Command] {
        let control = Category.control
        let navigation = Category.navigation
        return [
            shortcut(
                "stop-all",
                "Stop all",
                category: control,
                keywords: ["cancel", "abort", "halt"],
                isEnabled: composerIsSending || terminalIsRunning || hasActiveMCPServer
            ),
            command(
                "disconnect-all",
                "Disconnect all",
                category: control,
                keywords: ["disconnect", "remote", "mcp", "server", "connection"],
                isEnabled: hasSelectedRemoteProject || hasActiveMCPServer
            ),
            shortcut(
                "settings",
                "Settings",
                category: navigation,
                keywords: ["preferences", "trustedrouter", "auth"]
            ),
            shortcut(
                "command-palette",
                "Command palette",
                category: navigation,
                keywords: ["commands", "actions"]
            ),
            shortcut(
                "keyboard-shortcuts",
                "Keyboard shortcuts",
                category: navigation,
                keywords: ["keyboard", "shortcuts", "help", "commands"]
            )
        ]
    }

    static func computerUseCommands(computerUseStatus: ComputerUseStatus) -> [Command] {
        [
            .computerUseSetup(isEnabled: !computerUseStatus.available),
            .computerUseScreenRecordingSettings(isEnabled: !computerUseStatus.screenRecordingGranted),
            .computerUseAccessibilitySettings(isEnabled: !computerUseStatus.accessibilityGranted),
            .computerUseRefresh
        ]
    }

    private enum Category {
        static let control = WorkspaceCommandPalette.controlCategory
        static let extensions = WorkspaceCommandPalette.extensionsCategory
        static let memories = WorkspaceCommandPalette.memoriesCategory
        static let navigation = WorkspaceCommandPalette.navigationCategory
        static let workspace = WorkspaceCommandPalette.workspaceCategory
    }

    private static func shortcut(
        _ id: String,
        _ title: String,
        category: String = Category.workspace,
        keywords: [String],
        isEnabled: Bool = true
    ) -> Command {
        command(
            id,
            title,
            shortcut: WorkspaceShortcutRegistry.label(for: id),
            category: category,
            keywords: keywords,
            isEnabled: isEnabled
        )
    }

    private static func command(
        _ id: String,
        _ title: String,
        shortcut: String? = nil,
        category: String = Category.workspace,
        keywords: [String],
        isEnabled: Bool = true
    ) -> Command {
        Command(
            id: id,
            title: title,
            shortcut: shortcut,
            category: category,
            keywords: keywords,
            isEnabled: isEnabled
        )
    }
}
