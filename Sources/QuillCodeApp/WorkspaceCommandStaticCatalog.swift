import Foundation
import QuillComputerUseKit

enum WorkspaceCommandStaticCatalog {
    static func retryCommands(canRetryLastUserTurn: Bool) -> [WorkspaceCommandSurface] {
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

    static func navigationCommands(hasSelectedThread: Bool) -> [WorkspaceCommandSurface] {
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

    static func workspaceCommands(
        hasSelectedProject: Bool,
        terminalHasEntries: Bool,
        terminalIsRunning: Bool,
        browserCanGoBack: Bool,
        browserCanGoForward: Bool,
        browserCanReload: Bool,
        browserCanOpenSession: Bool
    ) -> [WorkspaceCommandSurface] {
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
                isEnabled: hasSelectedProject
            ),
            WorkspaceCommandSurface(
                id: "project-refresh-context",
                title: "Refresh project context",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["project", "workspace", "instructions", "memory", "reload"],
                isEnabled: hasSelectedProject
            ),
            WorkspaceCommandSurface(
                id: "project-rename",
                title: "Rename project",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["project", "workspace", "title", "name"],
                isEnabled: hasSelectedProject
            ),
            WorkspaceCommandSurface(
                id: "project-remove",
                title: "Remove project from list",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["project", "workspace", "forget", "remove"],
                isEnabled: hasSelectedProject
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
                shortcut: WorkspaceShortcutRegistry.label(for: "browser-back"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "history", "back"],
                isEnabled: browserCanGoBack
            ),
            WorkspaceCommandSurface(
                id: "browser-forward",
                title: "Browser: Forward",
                shortcut: WorkspaceShortcutRegistry.label(for: "browser-forward"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "history", "forward"],
                isEnabled: browserCanGoForward
            ),
            WorkspaceCommandSurface(
                id: "browser-reload",
                title: "Browser: Reload",
                shortcut: WorkspaceShortcutRegistry.label(for: "browser-reload"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "refresh", "reload"],
                isEnabled: browserCanReload
            ),
            WorkspaceCommandSurface(
                id: "open-browser-session",
                title: "Browser: Open session",
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "session", "login", "cookies", "sign in"],
                isEnabled: browserCanOpenSession
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

    static func automationCommands(
        hasSelectedThread: Bool,
        hasSelectedProject: Bool
    ) -> [WorkspaceCommandSurface] {
        [
            .automationCreateThreadFollowUp(isEnabled: hasSelectedThread),
            .automationCreateWorkspaceSchedule(isEnabled: hasSelectedProject)
        ] + WorkspaceCommandSurface.automationScheduleThreadFollowUpCommands(
            isEnabled: hasSelectedThread
        ) + WorkspaceCommandSurface.automationScheduleWorkspaceScheduleCommands(
            isEnabled: hasSelectedProject
        )
    }

    static func memoryCommands() -> [WorkspaceCommandSurface] {
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

    static func extensionToggleCommands(hasActiveWorkspaceRoot: Bool) -> [WorkspaceCommandSurface] {
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

    static func controlAndSettingsCommands(
        composerIsSending: Bool,
        terminalIsRunning: Bool,
        hasActiveMCPServer: Bool,
        hasSelectedRemoteProject: Bool
    ) -> [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "stop-all",
                title: "Stop all",
                shortcut: WorkspaceShortcutRegistry.label(for: "stop-all"),
                category: WorkspaceCommandPalette.controlCategory,
                keywords: ["cancel", "abort", "halt"],
                isEnabled: composerIsSending || terminalIsRunning || hasActiveMCPServer
            ),
            WorkspaceCommandSurface(
                id: "disconnect-all",
                title: "Disconnect all",
                category: WorkspaceCommandPalette.controlCategory,
                keywords: ["disconnect", "remote", "mcp", "server", "connection"],
                isEnabled: hasSelectedRemoteProject || hasActiveMCPServer
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

    static func computerUseCommands(computerUseStatus: ComputerUseStatus) -> [WorkspaceCommandSurface] {
        [
            .computerUseSetup(isEnabled: !computerUseStatus.available),
            .computerUseScreenRecordingSettings(isEnabled: !computerUseStatus.screenRecordingGranted),
            .computerUseAccessibilitySettings(isEnabled: !computerUseStatus.accessibilityGranted),
            .computerUseRefresh
        ]
    }
}
