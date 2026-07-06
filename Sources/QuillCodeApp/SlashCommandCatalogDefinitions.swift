extension SlashCommandCatalog {
    static let globalPrefixDefinitions: [SlashCommandDefinition] = [
        slashDefinition(
            "/help",
            "Show slash commands",
            "List the available composer commands.",
            aliases: ["?"]
        ),
        slashDefinition(
            "/status",
            "Show status",
            "Summarize the active project, mode, model, and loaded context."
        ),
        slashDefinition(
            "/new",
            "New chat",
            "Start a fresh thread in the selected project.",
            aliases: ["new-chat", "newchat"]
        ),
        slashDefinition(
            "/clear",
            "Clear chat",
            "Reset the current thread transcript and queued follow-ups without deleting the chat.",
            aliases: ["clear-chat", "reset-chat"]
        ),
        slashDefinition(
            "/undo",
            "Undo latest edit",
            "Reverse the latest revertable file edits from the current thread.",
            aliases: ["revert", "revert-latest", "undo-edit"]
        ),
        slashDefinition(
            "/rename title",
            "Rename chat",
            "Rename the current thread.",
            insert: "/rename ",
            aliases: ["rename-chat", "title"]
        ),
        slashDefinition(
            "/duplicate",
            "Duplicate chat",
            "Copy the current thread into a new one.",
            aliases: ["duplicate-chat", "copy-chat"]
        ),
        slashDefinition(
            "/pin",
            "Pin chat",
            "Keep the current thread in the pinned section.",
            aliases: ["pin-chat"]
        ),
        slashDefinition(
            "/unpin",
            "Unpin chat",
            "Remove the current thread from the pinned section.",
            aliases: ["unpin-chat"]
        ),
        slashDefinition(
            "/archive",
            "Archive chat",
            "Move the current thread out of the recent list.",
            aliases: ["archive-chat"]
        ),
        slashDefinition(
            "/unarchive",
            "Unarchive chat",
            "Restore the current archived thread.",
            aliases: ["unarchive-chat"]
        ),
        slashDefinition(
            "/delete",
            "Delete chat",
            "Remove the current chat from QuillCode without touching project files.",
            aliases: ["delete-chat", "remove-chat"]
        ),
        slashDefinition(
            "/fork last|summary|full",
            "Fork chat",
            "Create a continuation from the current chat using the latest turn, a summary, or full context.",
            insert: "/fork ",
            aliases: [
                "fork-last",
                "fork-from-last",
                "fork-summary",
                "fork-with-summary",
                "fork-full",
                "fork-full-context"
            ]
        ),
        slashDefinition(
            "/compact",
            "Compact context",
            "Create a shorter continuation thread from the latest turns.",
            aliases: ["compact-context", "context-compact"]
        ),
        slashDefinition(
            "/stop",
            "Stop active work",
            "Cancel the running agent turn, terminal command, or active extension work.",
            aliases: ["cancel", "abort"]
        ),
        slashDefinition(
            "/retry",
            "Retry last turn",
            "Prepare the latest user request to run again.",
            aliases: ["rerun", "again", "retry last"]
        ),
        slashDefinition(
            "/back",
            "Go back",
            "Return to the previous thread or project selection in workspace history.",
            aliases: ["previous", "prev", "history back"]
        ),
        slashDefinition(
            "/forward",
            "Go forward",
            "Move to the next thread or project selection in workspace history.",
            aliases: ["next", "history forward"]
        ),
        slashDefinition(
            "/history back|forward",
            "Navigate history",
            "Move through previous or next thread and project selections.",
            insert: "/history ",
            aliases: ["history previous", "history next"]
        ),
        slashDefinition(
            "/follow-up when",
            "Schedule follow-up",
            "Create a scheduled follow-up for this thread, for example in 30 minutes, Friday at 4 PM, "
                + "tonight, or daily.",
            insert: "/follow-up in ",
            aliases: ["followup", "schedule follow-up", "remind", "automation"]
        ),
        slashDefinition(
            "/workspace-check when",
            "Schedule workspace check",
            "Create a scheduled check for the selected project, for example in 1 hour, Friday morning, "
                + "next Monday at noon, or every 2 hours.",
            insert: "/workspace-check in ",
            aliases: [
                "workspace schedule",
                "schedule workspace",
                "project check",
                "repo check",
                "automation workspace"
            ]
        ),
        slashDefinition(
            "/subagents objective | Name: role",
            "Run subagents",
            "Fan out a local parallel subagent workflow and show replayable progress in Activity.",
            insert: "/subagents ",
            aliases: ["subagent", "parallel agents", "agents"]
        ),
        slashDefinition(
            "/project open",
            "Open project",
            "Open a local project folder and add it to the sidebar.",
            aliases: ["project add", "open project"]
        ),
        slashDefinition(
            "/project new",
            "Project new chat",
            "Start a new thread in the selected project.",
            aliases: ["project chat"]
        ),
        slashDefinition(
            "/project refresh",
            "Refresh project context",
            "Reload instructions, local actions, extensions, and memories.",
            aliases: ["project reload", "project context"]
        ),
        slashDefinition(
            "/init",
            "Initialize AGENTS.md",
            "Scaffold a starter AGENTS.md for the project from its build and test commands.",
            aliases: ["init-project", "scaffold", "agents"]
        ),
        slashDefinition(
            "/project rename name",
            "Rename project",
            "Rename the selected project in QuillCode.",
            insert: "/project rename ",
            aliases: ["project title"]
        ),
        slashDefinition(
            "/project remove",
            "Remove project",
            "Forget the selected project from the sidebar without deleting files.",
            aliases: ["project forget"]
        ),
        slashDefinition(
            "/ssh user@host:/path",
            "Add SSH Remote",
            "Register an SSH Remote workspace in the project sidebar.",
            insert: "/ssh ",
            aliases: ["remote", "ssh project"]
        ),
        slashDefinition(
            "/terminal",
            "Toggle terminal",
            "Show or hide the integrated workspace terminal.",
            aliases: ["term", "shell"]
        ),
        slashDefinition(
            "/terminal clear",
            "Clear terminal history",
            "Clear completed integrated-terminal history without resetting cwd or environment.",
            aliases: ["term clear", "shell clear"]
        ),
        slashDefinition(
            "/search",
            "Search chats",
            "Open global search across thread titles, transcript text, tools, models, and pinned or archived state.",
            aliases: ["global search", "chat search"]
        ),
        slashDefinition(
            "/find",
            "Find in chat",
            "Open the active chat finder with result count and next/previous navigation.",
            aliases: ["find in chat", "transcript find"]
        ),
        slashDefinition(
            "/focus",
            "Focus message input",
            "Move keyboard focus back to the composer.",
            aliases: ["composer", "input", "message input"]
        ),
        slashDefinition(
            "/sidebar",
            "Toggle sidebar",
            "Show or hide the chat and project sidebar.",
            aliases: ["toggle sidebar", "hide sidebar", "show sidebar"]
        ),
        slashDefinition(
            "/copy",
            "Copy conversation",
            "Copy the visible conversation as Markdown.",
            aliases: ["copy conversation", "copy transcript"]
        ),
        slashDefinition(
            "/export",
            "Export conversation",
            "Export the visible conversation as Markdown.",
            aliases: ["export markdown", "export conversation", "save transcript"]
        ),
        slashDefinition(
            "/settings",
            "Settings",
            "Open TrustedRouter, Computer Use, browser, and notification settings.",
            aliases: ["preferences", "prefs"]
        ),
        slashDefinition(
            "/shortcuts",
            "Keyboard shortcuts",
            "Open the keyboard shortcut reference.",
            aliases: ["keyboard shortcuts", "keys"]
        ),
        slashDefinition(
            "/commands",
            "Command palette",
            "Open the searchable command palette.",
            aliases: ["command-palette", "palette"]
        ),
        slashDefinition(
            "/extensions",
            "Toggle extensions",
            "Show or hide project plugins, skills, MCP servers, and marketplace entries.",
            aliases: ["plugins", "skills"]
        ),
        slashDefinition(
            "/skills",
            "Show skills",
            "Open the Extensions pane filtered around installed and available skills.",
            aliases: ["skill list", "installed skills", "available skills"]
        ),
        slashDefinition(
            "/automations",
            "Toggle automations",
            "Show or hide scheduled follow-ups, workspace checks, and automation history."
        ),
        slashDefinition(
            "/activity",
            "Toggle activity",
            "Show or hide task plans, tool history, artifacts, sources, and handoff notes."
        ),
        slashDefinition(
            "/browser",
            "Toggle browser",
            "Show or hide the browser preview panel.",
            aliases: ["preview"]
        ),
        slashDefinition(
            "/review",
            "Review changes",
            "Show the working-tree git diff in the review pane.",
            aliases: ["review diff", "review changes"]
        ),
        slashDefinition(
            "/diff",
            "Review diff",
            "Show the working-tree git diff in the review pane.",
            aliases: ["changes", "git diff", "review"]
        ),
        slashDefinition(
            "/git-status",
            "Git status",
            "Show the git status of the selected project.",
            aliases: ["gitstatus", "git status"]
        ),
        slashDefinition(
            "/git fetch",
            "Fetch latest refs",
            "Fetch from the selected project's remote without changing the working tree.",
            insert: "/git fetch",
            aliases: ["git fetch origin", "fetch"]
        ),
        slashDefinition(
            "/git pull",
            "Pull latest changes",
            "Pull the selected project's latest upstream changes with --ff-only by default.",
            insert: "/git pull",
            aliases: ["git sync", "pull latest"]
        ),
        slashDefinition(
            "/branch",
            "List branches",
            "List local and remote-tracking branches for the selected project.",
            aliases: ["branches", "git branch"]
        ),
        slashDefinition(
            "/branch switch name",
            "Switch branch",
            "Switch the selected project to an existing branch.",
            insert: "/branch switch ",
            aliases: ["branch checkout", "git switch"]
        ),
        slashDefinition(
            "/branch create name",
            "Create branch",
            "Create and switch to a new branch. Add --from ref to choose the start point.",
            insert: "/branch create ",
            aliases: ["branch new", "git switch -c"]
        ),
        slashDefinition(
            "/memories",
            "Show memories",
            "Show loaded global and project memories.",
            aliases: ["memory"]
        ),
        slashDefinition(
            "/remember text",
            "Add memory",
            "Save an explicit global memory after redaction checks.",
            insert: "/remember "
        ),
        slashDefinition(
            "/worktrees",
            "List worktrees",
            "List git worktrees for the selected project.",
            aliases: ["worktree", "wt"]
        ),
        slashDefinition(
            "/worktree create path",
            "Create worktree",
            "Create and open a sibling git worktree. Add --branch name or --base ref when needed.",
            insert: "/worktree create ",
            aliases: ["worktree add", "wt create"]
        ),
        slashDefinition(
            "/worktree open path",
            "Open worktree",
            "Open an existing registered git worktree as a focused project.",
            insert: "/worktree open ",
            aliases: ["worktree switch", "wt open"]
        ),
        slashDefinition(
            "/worktree remove path",
            "Remove worktree",
            "Remove an existing registered git worktree. Add --force only when needed.",
            insert: "/worktree remove ",
            aliases: ["worktree rm", "wt remove"]
        ),
        slashDefinition(
            "/worktree prune",
            "Prune stale worktrees",
            "Clean stale git worktree administrative records. Add --dry-run to preview.",
            insert: "/worktree prune --dry-run",
            aliases: ["worktree cleanup", "wt prune"]
        )
    ]

    static let globalSuffixDefinitions: [SlashCommandDefinition] = [
        slashDefinition(
            "/env name",
            "Run local environment action",
            "List or run project-local environment scripts.",
            insert: "/env ",
            aliases: ["environment", "local-env"]
        ),
        slashDefinition(
            "/env schedule name when",
            "Schedule local environment action",
            "Run a project-local environment script later or on a recurrence.",
            insert: "/env schedule ",
            aliases: ["environment schedule", "local-env schedule"]
        ),
        slashDefinition(
            "/mode auto|plan|review|read-only",
            "Set approval mode",
            "Switch between Auto, Plan, Review, and Read-only behavior.",
            insert: "/mode "
        ),
        slashDefinition(
            "/plan",
            "Enter Plan mode",
            "Investigate read-only and propose a plan; mutating tools wait for your approval."
        ),
        slashDefinition(
            "/model name",
            "Set model",
            "Search the TrustedRouter catalog with live per-1M pricing and switch the thread's model.",
            insert: "/model ",
            aliases: ["models", "switch model", "change model"]
        ),
        slashDefinition(
            "/skill name",
            "Run a skill",
            "Load an installed skill by name and follow it, for example /skill code-review.",
            insert: "/skill ",
            aliases: ["run skill", "load skill"]
        )
    ]

    static func slashDefinition(
        _ usage: String,
        _ title: String,
        _ detail: String,
        insert insertText: String? = nil,
        aliases: [String] = []
    ) -> SlashCommandDefinition {
        SlashCommandDefinition(
            usage: usage,
            title: title,
            detail: detail,
            insertText: insertText ?? usage,
            aliases: aliases
        )
    }
}
