import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceSurfaceTests: XCTestCase {
    func testSurfaceIncludesTopBarSidebarComposerAndCommands() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Run whoami", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "Output:\njperla")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.setDraft("git status")

        let surface = model.surface()

        XCTAssertEqual(surface.topBar.primaryTitle, "Run whoami")
        XCTAssertEqual(surface.topBar.modelLabel, TrustedRouterDefaults.fastModelDisplayName)
        XCTAssertEqual(surface.topBar.selectedModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertTrue(surface.topBar.modelCategories.contains { $0.category == "Recommended" })
        XCTAssertTrue(surface.topBar.modelCategories.flatMap(\.models).contains { $0.id == TrustedRouterDefaults.defaultModel && $0.isSelected })
        let recommendedModelIDs = surface.topBar.modelCategories
            .first { $0.category == "Recommended" }?
            .models
            .prefix(3)
            .map(\.id) ?? []
        XCTAssertEqual(recommendedModelIDs, TrustedRouterDefaults.recommendedModelIDs)
        let defaultOption = surface.topBar.modelCategories
            .flatMap(\.models)
            .first { $0.id == TrustedRouterDefaults.defaultModel }
        XCTAssertEqual(defaultOption?.metadataSummary, "Fast everyday agent")
        XCTAssertTrue(defaultOption?.metadataDetails.contains("Default model") == true)
        XCTAssertTrue(defaultOption?.metadataDetails.contains("Recommended by QuillCode") == true)
        XCTAssertEqual(surface.topBar.modeLabel, "Auto")
        XCTAssertEqual(surface.topBar.instructionLabel, "No project instructions")
        XCTAssertEqual(surface.topBar.instructionSources, [])
        XCTAssertEqual(surface.topBar.memoryLabel, "No memories")
        XCTAssertEqual(surface.topBar.memorySources, [])
        XCTAssertEqual(surface.projects.items.count, 1)
        XCTAssertEqual(surface.projects.items[0].name, "QuillCode")
        XCTAssertEqual(surface.projects.items[0].path, "/tmp/QuillCode")
        XCTAssertEqual(surface.projects.items[0].connectionKindLabel, "Local")
        XCTAssertFalse(surface.projects.items[0].isRemote)
        XCTAssertTrue(surface.projects.items[0].isSelected)
        XCTAssertEqual(surface.projects.items[0].actions.map(\.kind), [.newChat, .refreshContext, .rename, .remove])
        XCTAssertTrue(surface.projects.items[0].actions.allSatisfy(\.isEnabled))
        XCTAssertEqual(surface.sidebar.items.count, 1)
        XCTAssertEqual(surface.sidebar.items[0].title, "Run whoami")
        XCTAssertTrue(surface.sidebar.items[0].isSelected)
        XCTAssertFalse(surface.sidebar.items[0].isBulkSelected)
        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectionLabel, "No chats selected")
        XCTAssertEqual(surface.sidebar.bulkActions.map(\.kind), [.select])
        XCTAssertEqual(surface.sidebar.items[0].actions.map(\.kind), [.rename, .duplicate, .pin, .archive, .delete])
        XCTAssertEqual(surface.transcript.messages.count, 2)
        XCTAssertEqual(surface.composer.placeholder, "Message QuillCode")
        XCTAssertTrue(surface.composer.canSend)
        XCTAssertEqual(surface.composer.slashSuggestions, [])
        XCTAssertEqual(surface.commands.map(\.id), [
            "new-chat",
            "thread-rename",
            "thread-duplicate",
            "thread-archive",
            "thread-unarchive",
            "thread-delete",
            "thread-selection-start",
            "thread-selection-select-all",
            "thread-selection-clear",
            "thread-bulk-pin",
            "thread-bulk-unpin",
            "thread-bulk-archive",
            "thread-bulk-unarchive",
            "thread-bulk-delete",
            "fork-from-last",
            "compact-context",
            "retry-last-turn",
            "search",
            "find-in-chat",
            "add-project",
            "add-ssh-project",
            "project-new-chat",
            "project-refresh-context",
            "project-rename",
            "project-remove",
            "toggle-terminal",
            "terminal-clear",
            "toggle-browser",
            "browser-back",
            "browser-forward",
            "browser-reload",
            "open-browser-session",
            "toggle-activity",
            "toggle-automations",
            "automation-create-thread-follow-up",
            "automation-create-workspace-schedule",
            "automation-create-thread-follow-up-after:600",
            "automation-create-thread-follow-up-after:3600",
            "automation-create-thread-follow-up-tomorrow",
            "automation-create-thread-follow-up-every:daily",
            "automation-create-workspace-schedule-after:600",
            "automation-create-workspace-schedule-after:3600",
            "automation-create-workspace-schedule-tomorrow",
            "automation-create-workspace-schedule-every:daily",
            "toggle-memories",
            "memory-add",
            "toggle-extensions",
            "git-status",
            "git-diff",
            "git-pr-create",
            "git-pr-view",
            "git-pr-checks",
            "git-pr-diff",
            "git-pr-checkout",
            "git-pr-reviewers",
            "git-pr-comment",
            "git-pr-review",
            "git-pr-labels",
            "git-pr-merge",
            "git-worktree-list",
            "git-worktree-create",
            "git-worktree-remove",
            "stop-all",
            "disconnect-all",
            "settings",
            "command-palette",
            "keyboard-shortcuts",
            "computer-use-setup",
            "computer-use-open-screen-recording",
            "computer-use-open-accessibility",
            "computer-use-refresh"
        ])
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "find-in-chat" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "open-browser-session" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "disconnect-all" }?.isEnabled, false)
        XCTAssertFalse(surface.terminal.isVisible)
        XCTAssertEqual(surface.terminal.cwdLabel, "/tmp/QuillCode")
        XCTAssertFalse(surface.browser.isVisible)
        XCTAssertFalse(surface.extensions.isVisible)
        XCTAssertFalse(surface.memories.isVisible)
        XCTAssertFalse(surface.activity.isVisible)
    }

    func testSurfaceMarksSSHProjectsAndEnablesRemoteGitCommands() throws {
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(
            name: "Feather",
            path: connection.path,
            connection: connection
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id
        ))

        let surface = model.surface()
        let item = try XCTUnwrap(surface.projects.items.first)

        XCTAssertEqual(item.name, "Feather")
        XCTAssertEqual(item.path, "ssh://quill@feather.local:2222/srv/quill")
        XCTAssertEqual(item.connectionKindLabel, "SSH Remote")
        XCTAssertTrue(item.isRemote)
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .rename, .remove])
        XCTAssertEqual(item.actions.first { $0.kind == .refreshContext }?.isEnabled, true)
        XCTAssertNil(item.actions.first { $0.kind == .refreshContext }?.disabledReason)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-status" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-diff" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-view" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checks" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-diff" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checkout" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-reviewers" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-comment" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-labels" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-merge" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-list" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-remove" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "add-ssh-project" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "add-ssh-project" }?.title, "Project: Add SSH Remote...")
        XCTAssertEqual(surface.commands.first { $0.id == "disconnect-all" }?.isEnabled, true)
        XCTAssertEqual(surface.terminal.cwdLabel, "ssh://quill@feather.local:2222/srv/quill")
    }

    func testDisconnectAllDetachesSelectedSSHProjectWithoutRemovingIt() throws {
        let connection = ProjectConnection.ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let thread = ChatThread(title: "Remote work", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertEqual(model.surface().commands.first { $0.id == "disconnect-all" }?.isEnabled, true)
        XCTAssertTrue(model.runWorkspaceCommand("disconnect-all", workspaceRoot: try makeTempDirectory()))
        XCTAssertNil(model.root.selectedProjectID)
        XCTAssertNil(model.root.selectedThreadID)
        XCTAssertEqual(model.root.projects, [project])
        XCTAssertEqual(model.root.threads.first?.projectID, project.id)
        XCTAssertEqual(model.surface().commands.first { $0.id == "disconnect-all" }?.isEnabled, false)
    }

    func testSidebarBulkSelectionArchivesAndDeletesChats() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let first = ChatThread(title: "Run whoami", projectID: project.id)
        let second = ChatThread(title: "Check diff", projectID: project.id)
        let fallback = ChatThread(title: "Review tests", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [first, second, fallback],
            selectedThreadID: first.id
        ))

        model.startSidebarSelection(selecting: first.id)
        model.toggleSidebarThreadSelection(second.id)

        var surface = model.surface()
        XCTAssertTrue(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectionLabel, "2 chats selected")
        XCTAssertEqual(Set(surface.sidebar.items.filter(\.isBulkSelected).map(\.id)), [first.id, second.id])
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .archive }?.isEnabled, true)

        XCTAssertTrue(model.performSidebarBulkAction(.archive))
        surface = model.surface()

        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(Set(surface.sidebar.archivedItems.map(\.id)), [first.id, second.id])
        XCTAssertEqual(surface.sidebar.selectedThreadID, fallback.id)

        model.selectAllSidebarThreads()
        surface = model.surface()
        XCTAssertEqual(surface.sidebar.selectionLabel, "3 chats selected")
        XCTAssertTrue(model.performSidebarBulkAction(.delete))

        surface = model.surface()
        XCTAssertEqual(surface.sidebar.items.count, 0)
        XCTAssertNil(surface.sidebar.selectedThreadID)
        XCTAssertFalse(surface.sidebar.isSelectionMode)
    }

    func testSidebarSearchExcludesHiddenToolFeedback() {
        let thread = ChatThread(title: "Visible thread", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .tool, content: #"{"result":"secret internal feedback"}"#),
            .init(role: .assistant, content: "Output:\nquill")
        ])

        let item = SidebarItem(thread: thread)
        let sidebar = SidebarSurface(
            items: [SidebarItemSurface(item: item, selectedThreadID: thread.id)],
            selectedThreadID: thread.id
        )

        XCTAssertEqual(sidebar.filteredItems(matching: "secret internal feedback"), [])
        XCTAssertEqual(sidebar.filteredItems(matching: "whoami").map(\.id), [thread.id])
    }

    func testComposerShowsFilteredSlashSuggestions() {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/")
        var suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.prefix(3).map(\.usage), ["/help", "/status", "/new"])

        model.setDraft("/workt")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/worktrees")
        XCTAssertEqual(suggestions.first?.insertText, "/worktrees")

        model.setDraft("/fol")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/follow-up when")
        XCTAssertEqual(suggestions.first?.insertText, "/follow-up in ")

        model.setDraft("/workspace-c")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/workspace-check when")
        XCTAssertEqual(suggestions.first?.insertText, "/workspace-check in ")

        model.setDraft("/project r")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.prefix(2).map(\.usage), ["/project refresh", "/project rename name"])

        model.setDraft("/pr l")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/pr labels add|remove label")
        XCTAssertEqual(suggestions.first?.insertText, "/pr labels add ")

        model.setDraft("run /help")
        XCTAssertEqual(model.surface().composer.slashSuggestions, [])
    }

    func testShortcutRegistryLabelsSurfaceCommands() {
        let model = QuillCodeWorkspaceModel()
        let commandsByID = Dictionary(uniqueKeysWithValues: model.surface().commands.map { ($0.id, $0) })

        for shortcut in WorkspaceShortcutRegistry.shortcuts {
            XCTAssertEqual(
                commandsByID[shortcut.commandID]?.shortcut,
                shortcut.displayLabel,
                shortcut.commandID
            )
        }
    }

    func testShortcutRegistryHasNoDuplicateBindings() {
        let bindings = WorkspaceShortcutRegistry.shortcuts.map {
            "\($0.modifiers.map(\.rawValue).joined(separator: "+"))+\($0.key)"
        }

        XCTAssertEqual(Set(bindings).count, bindings.count)
    }

    func testCommandPaletteRanksByShortcutKeywordsAndTitle() {
        let model = QuillCodeWorkspaceModel()
        let commands = model.surface().commands

        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "shell").first?.id,
            "toggle-terminal"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "cmd+k").first?.id,
            "search"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "cmd+f").first?.id,
            "find-in-chat"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "create pull").first?.id,
            "git-pr-create"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "checks").first?.id,
            "git-pr-checks"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "pr diff").first?.id,
            "git-pr-diff"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "checkout pull").first?.id,
            "git-pr-checkout"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "request reviewers").first?.id,
            "git-pr-reviewers"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "comment pull").first?.id,
            "git-pr-comment"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "approve pr").first?.id,
            "git-pr-review"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "label pr").first?.id,
            "git-pr-labels"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "merge pull").first?.id,
            "git-pr-merge"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "cmd+/").first?.id,
            "keyboard-shortcuts"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "shortcuts").first?.id,
            "keyboard-shortcuts"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: ">shell").first?.id,
            "toggle-terminal"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "/mode").first?.title,
            "/mode auto|review|read-only"
        )
        XCTAssertFalse(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "")
                .contains { $0.id.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) }
        )
        XCTAssertTrue(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "mode")
                .contains { $0.id.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) }
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.groupedCommands(commands, matching: "/").map(\.title),
            [WorkspaceCommandPalette.slashCategory]
        )
    }

    func testCommandPaletteGroupsFilteredResultsByCategory() {
        let model = QuillCodeWorkspaceModel()
        let groups = WorkspaceCommandPalette.groupedCommands(model.surface().commands, matching: ">worktree")

        XCTAssertEqual(groups.map(\.title), [WorkspaceCommandPalette.gitCategory])
        XCTAssertEqual(groups.first?.commands.map(\.id), [
            "git-worktree-list",
            "git-worktree-create",
            "git-worktree-remove"
        ])
    }

    func testWorkspaceCommandSurfaceDecodesOlderPayloadWithoutCategoryMetadata() throws {
        let data = #"{"id":"search","title":"Search","shortcut":"Cmd+K","isEnabled":true}"#.data(using: .utf8)!

        let command = try JSONDecoder().decode(WorkspaceCommandSurface.self, from: data)

        XCTAssertEqual(command.category, WorkspaceCommandPalette.workspaceCategory)
        XCTAssertEqual(command.keywords, [])
    }

    func testContextBannerDecodesOlderPayloadWithoutCompactCommand() throws {
        let data = """
        {
          "usedPercent": 88,
          "title": "Approaching context limit",
          "subtitle": "Older turns may drop out soon.",
          "newThreadCommand": {"id":"new-chat","title":"New thread"},
          "forkCommand": {"id":"fork-from-last","title":"Fork from last","isEnabled":true}
        }
        """.data(using: .utf8)!

        let banner = try JSONDecoder().decode(ContextBannerSurface.self, from: data)

        XCTAssertEqual(banner.usedPercent, 88)
        XCTAssertEqual(banner.compactCommand.id, "compact-context")
        XCTAssertEqual(banner.compactCommand.title, "Compact context")
        XCTAssertEqual(banner.compactCommand.category, WorkspaceCommandPalette.threadCategory)
        XCTAssertEqual(banner.compactCommand.isEnabled, true)
    }

    func testSurfaceIncludesLocalEnvironmentActionCommands() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            localActions: [
                LocalEnvironmentAction(
                    id: "local-env:.quillcode/actions/bootstrap.sh",
                    title: "Bootstrap",
                    detail: "Install dependencies and warm caches.",
                    relativePath: ".quillcode/actions/bootstrap.sh",
                    command: "sh '.quillcode/actions/bootstrap.sh'",
                    environment: ["QUILL_ENV": "dev"],
                    workingDirectory: "app",
                    timeoutSeconds: 120
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id
        ))

        let command = model.surface().commands.first {
            $0.id == "local-env:.quillcode/actions/bootstrap.sh"
        }

        XCTAssertEqual(command?.title, "Run Bootstrap")
        XCTAssertEqual(command?.isEnabled, true)
        XCTAssertTrue(command?.keywords.contains("Install dependencies and warm caches.") == true)
        XCTAssertTrue(command?.keywords.contains("QUILL_ENV") == true)
        XCTAssertTrue(command?.keywords.contains("app") == true)
        XCTAssertTrue(command?.keywords.contains("120s") == true)
    }

    func testSurfaceIncludesProjectExtensionSummaryAndCommand() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "plugin:github",
                    kind: .plugin,
                    name: "GitHub",
                    summary: "PR workflow helpers.",
                    version: "1.2.0",
                    sourceURL: "https://github.com/Lore-Hex/quillcode-github",
                    relativePath: ".quillcode/plugins/github.json",
                    updateCommand: "git -C .quillcode/plugins/github pull --ff-only",
                    updateTimeoutSeconds: 300
                ),
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    summary: "Workspace MCP server.",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    transport: .stdio,
                    launchExecutable: "quill-mcp",
                    launchCommand: "quill-mcp --root .",
                    launchArguments: ["--root", "."]
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(isVisible: true)
        )

        let surface = model.surface()

        XCTAssertEqual(surface.extensions.subtitle, "1 plugin · 0 skills · 1 MCP server")
        XCTAssertEqual(surface.extensions.items.map(\.kindLabel), ["Plugin", "MCP"])
        XCTAssertEqual(surface.extensions.items.map(\.statusLabel), ["Discovered", "Stopped"])
        XCTAssertEqual(surface.extensions.items.first?.versionLabel, "v1.2.0")
        XCTAssertEqual(surface.extensions.items.first?.sourceURL, "https://github.com/Lore-Hex/quillcode-github")
        XCTAssertEqual(surface.extensions.items.first?.updateCommandID, "extension-update:plugin:github")
        XCTAssertEqual(surface.commands.first { $0.id == "extension-update:plugin:github" }?.title, "Update GitHub")
        XCTAssertEqual(surface.commands.first { $0.id == "extension-update:plugin:github" }?.isEnabled, true)
        XCTAssertEqual(surface.extensions.items.last?.transportLabel, "STDIO")
        XCTAssertEqual(surface.extensions.items.last?.launchCommand, "quill-mcp --root .")
        XCTAssertEqual(surface.extensions.items.last?.startCommandID, "mcp-start:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-start:mcp_server:filesystem" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-stop:mcp_server:filesystem" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-extensions" }?.category, WorkspaceCommandPalette.extensionsCategory)
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-extensions" }?.isEnabled, true)
    }

    func testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    transport: .stdio,
                    launchExecutable: "quill-mcp",
                    launchCommand: "quill-mcp --root .",
                    launchArguments: ["--root", "."]
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(
                isVisible: true,
                mcpServerStatuses: ["mcp_server:filesystem": .ready],
                mcpServerProbeSummaries: [
                    "mcp_server:filesystem": MCPServerProbeSummary(
                        protocolVersion: "2024-11-05",
                        serverName: "Fixture MCP",
                        serverVersion: "1.0.0",
                        toolDescriptors: [
                            MCPToolDescriptor(
                                name: "read_file",
                                description: "Read a file",
                                requiredArguments: ["path"],
                                schemaSummary: "required: path:string"
                            ),
                            MCPToolDescriptor(
                                name: "write_file",
                                requiredArguments: ["content", "path"],
                                optionalArguments: ["overwrite"],
                                schemaSummary: "required: content:string, path:string; optional: overwrite:boolean"
                            )
                        ],
                        resourceNames: ["README", "Project config"],
                        promptNames: ["summarize_project"]
                    )
                ]
            )
        )

        let surface = model.surface()

        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Ready")
        XCTAssertEqual(surface.extensions.items.first?.serverLabel, "Fixture MCP 1.0.0")
        XCTAssertEqual(surface.extensions.items.first?.protocolLabel, "MCP 2024-11-05")
        XCTAssertEqual(surface.extensions.items.first?.toolCountLabel, "2 tools")
        XCTAssertEqual(surface.extensions.items.first?.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(surface.extensions.items.first?.toolDescriptors.map(\.schemaSummary), [
            "required: path:string",
            "required: content:string, path:string; optional: overwrite:boolean"
        ])
        XCTAssertEqual(surface.extensions.items.first?.resourceCountLabel, "2 resources")
        XCTAssertEqual(surface.extensions.items.first?.resourceNames, ["README", "Project config"])
        XCTAssertEqual(surface.extensions.items.first?.promptCountLabel, "1 prompt")
        XCTAssertEqual(surface.extensions.items.first?.promptNames, ["summarize_project"])
        XCTAssertNil(surface.extensions.items.first?.startCommandID)
        XCTAssertEqual(surface.extensions.items.first?.stopCommandID, "mcp-stop:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-start:mcp_server:filesystem" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-stop:mcp_server:filesystem" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, true)
    }

    func testSurfaceIncludesMemorySummariesAndCommand() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            memories: [
                MemoryNote(
                    id: "project:.quillcode/memories/project.md",
                    scope: .project,
                    title: "Project",
                    content: "QuillCode should stay native Swift and document major decisions.",
                    relativePath: ".quillcode/memories/project.md",
                    byteCount: 63
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                globalMemories: [
                    MemoryNote(
                        id: "global:memories/preferences.md",
                        scope: .global,
                        title: "Preferences",
                        content: "Prefer focused tests and small reviewable commits.",
                        relativePath: "memories/preferences.md",
                        byteCount: 48
                    )
                ]
            ),
            memories: MemoriesState(isVisible: true)
        )

        let surface = model.surface()

        XCTAssertTrue(surface.memories.isVisible)
        XCTAssertEqual(surface.memories.globalCount, 1)
        XCTAssertEqual(surface.memories.projectCount, 1)
        XCTAssertEqual(surface.memories.items.map { $0.scope }, [MemoryScope.global, .project])
        XCTAssertEqual(surface.memories.items.first?.title, "Preferences")
        XCTAssertEqual(surface.topBar.memoryLabel, "2 memories")
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-memories" }?.category, WorkspaceCommandPalette.memoriesCategory)
    }

    func testStopAllCommandIsEnabledForTerminalRuns() {
        let model = QuillCodeWorkspaceModel(terminal: TerminalState(isRunning: true))

        let command = model.surface().commands.first { $0.id == "stop-all" }

        XCTAssertEqual(command?.isEnabled, true)
    }

    func testEmptySurfaceShowsCodexLikeEmptyState() {
        let surface = QuillCodeWorkspaceModel().surface()

        XCTAssertEqual(surface.topBar.primaryTitle, "QuillCode")
        XCTAssertEqual(surface.sidebar.items.count, 0)
        XCTAssertEqual(surface.transcript.emptyTitle, "Ask QuillCode to inspect, edit, or run this project.")
        XCTAssertFalse(surface.review.isVisible)
        XCTAssertFalse(surface.composer.canSend)
        XCTAssertTrue(surface.topBar.showsComputerUseSetup)
    }

    func testContextBannerAppearsNearEstimatedLimit() throws {
        let longMessage = "context " + String(repeating: "word ", count: 26_000)
        let thread = ChatThread(title: "Long context", messages: [
            .init(role: .user, content: longMessage)
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let surface = model.surface()
        let banner = try XCTUnwrap(surface.contextBanner)

        XCTAssertTrue(banner.usedPercent >= 80)
        XCTAssertTrue(banner.title.contains("Context"))
        XCTAssertEqual(banner.newThreadCommand.id, "new-chat")
        XCTAssertEqual(banner.forkCommand.id, "fork-from-last")
        XCTAssertEqual(banner.compactCommand.id, "compact-context")
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, true)
    }

    func testContextBannerHiddenForShortThreadAndForkDisabledWithoutMessages() {
        let thread = ChatThread(title: "Short")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let surface = model.surface()

        XCTAssertNil(surface.contextBanner)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, false)
    }

    func testSidebarSearchFiltersByThreadTitleSubtitleAndTranscriptContent() {
        let selectedThread = ChatThread(title: "Run whoami", model: TrustedRouterDefaults.synthModel)
        var otherThread = ChatThread(title: "Review git diff", model: "z-ai/glm-5.2", isPinned: true)
        otherThread.messages = [
            .init(role: .user, content: "Can you inspect the browser preview?")
        ]
        var archivedThread = ChatThread(title: "Old release plan", model: TrustedRouterDefaults.synthModel)
        archivedThread.isArchived = true
        let surface = SidebarSurface(
            items: [
                SidebarItemSurface(item: SidebarItem(thread: selectedThread), selectedThreadID: selectedThread.id),
                SidebarItemSurface(item: SidebarItem(thread: otherThread), selectedThreadID: selectedThread.id),
                SidebarItemSurface(item: SidebarItem(thread: archivedThread), selectedThreadID: selectedThread.id)
            ],
            selectedThreadID: selectedThread.id
        )

        XCTAssertEqual(surface.filteredItems(matching: "").map(\.title), ["Run whoami", "Review git diff", "Old release plan"])
        XCTAssertEqual(surface.filteredItems(matching: "who").map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.filteredItems(matching: "GLM").map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.filteredItems(matching: "browser preview").map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.filteredItems(matching: "archived").map(\.title), ["Old release plan"])
        XCTAssertTrue(surface.filteredItems(matching: "workspace manager").isEmpty)
        XCTAssertEqual(surface.pinnedItems.map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.recentItems.map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.recentSections().map(\.title), ["Today"])
        XCTAssertEqual(surface.archivedItems.map(\.title), ["Old release plan"])
        XCTAssertEqual(surface.archivedItems.first?.actions.map(\.kind), [.unarchive, .delete])
    }

    func testGitDiffReviewSurfaceSummarizesLatestCompletedDiff() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111111..2222222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,3 +1,4 @@
         import Foundation
        -let title = "Old"
        +let title = "QuillCode"
        +let subtitle = "Review"
        diff --git a/README.md b/README.md
        index 3333333..4444444 100644
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -Old README
        +New README
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let thread = ChatThread(
            title: "Review changes",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolRunning, summary: "host.git.diff running"),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let review = model.surface().review

        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.files.map(\.path), ["Sources/App.swift", "README.md"])
        XCTAssertEqual(review.totalInsertions, 3)
        XCTAssertEqual(review.totalDeletions, 2)
        XCTAssertEqual(review.totalHunks, 2)
        XCTAssertEqual(review.subtitle, "2 files changed, +3 -2")
        XCTAssertEqual(review.files.first?.actions.map(\.kind), [.stage, .restore])
        XCTAssertEqual(review.files.first?.hunkItems.count, 1)
        XCTAssertEqual(review.files.first?.hunkItems.first?.actions.map(\.kind), [.stageHunk, .restoreHunk])
        XCTAssertTrue(review.files.first?.hunkItems.first?.patch.contains("diff --git a/Sources/App.swift b/Sources/App.swift") == true)
        let appLines = review.files.first?.hunkItems.first?.lines
        XCTAssertEqual(appLines?.map(\.kind), [.context, .deletion, .insertion, .insertion])
        XCTAssertEqual(appLines?.map(\.oldLineNumber), [1, 2, nil, nil])
        XCTAssertEqual(appLines?.map(\.newLineNumber), [1, nil, 2, 3])
    }

    func testGitDiffReviewSurfaceIncludesMatchingReviewComments() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1 +1,2 @@
        +let title = "QuillCode"
         import Foundation
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let matchingComment = WorkspaceReviewCommentState(path: "Sources/App.swift", text: "Check the public API name.")
        let lineComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            lineKind: .insertion,
            text: "This line should stay public."
        )
        let rangeComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            endLineNumber: 2,
            text: "Keep the title next to the import."
        )
        let staleComment = WorkspaceReviewCommentState(path: "README.md", text: "This file is no longer in the diff.")
        let thread = ChatThread(
            title: "Review changes",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift", payloadJSON: try JSONHelpers.encodePretty(matchingComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift:1", payloadJSON: try JSONHelpers.encodePretty(lineComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift:1-2", payloadJSON: try JSONHelpers.encodePretty(rangeComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on README.md", payloadJSON: try JSONHelpers.encodePretty(staleComment))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let review = model.surface().review

        XCTAssertEqual(review.files.count, 1)
        XCTAssertEqual(review.files.first?.comments.map(\.text), ["Check the public API name."])
        XCTAssertEqual(
            review.files.first?.hunkItems.first?.lines.first?.comments.map(\.text),
            ["This line should stay public.", "Keep the title next to the import."]
        )
        XCTAssertEqual(review.files.first?.hunkItems.first?.lines.first?.comments.last?.lineRangeLabel, "Lines 1-2")
    }

    func testGitDiffReviewSurfaceHidesStaleDiffWhenLatestDiffFailed() throws {
        let successfulCall = ToolCall(id: "git-diff-1", name: "host.git.diff", argumentsJSON: "{}")
        let failedCall = ToolCall(id: "git-diff-2", name: "host.git.diff", argumentsJSON: "{}")
        let successfulResult = ToolResult(ok: true, stdout: """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        @@ -1 +1 @@
        -old
        +new
        """)
        let failedResult = ToolResult(ok: false, error: "not a git repository")
        let thread = ChatThread(
            title: "Git diff",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(successfulCall)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(successfulResult)),
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(failedCall)),
                ThreadEvent(kind: .toolFailed, summary: "host.git.diff failed", payloadJSON: try JSONHelpers.encodePretty(failedResult))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertFalse(model.surface().review.isVisible)
    }

}
