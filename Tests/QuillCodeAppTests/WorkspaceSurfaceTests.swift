import XCTest
import QuillCodeAgent
import QuillCodeCore
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
        XCTAssertEqual(surface.topBar.modelLabel, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(surface.topBar.selectedModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertTrue(surface.topBar.modelCategories.contains { $0.category == "Recommended" })
        XCTAssertTrue(surface.topBar.modelCategories.flatMap(\.models).contains { $0.id == TrustedRouterDefaults.defaultModel && $0.isSelected })
        XCTAssertEqual(surface.topBar.modeLabel, "Auto")
        XCTAssertEqual(surface.topBar.instructionLabel, "No project instructions")
        XCTAssertEqual(surface.topBar.instructionSources, [])
        XCTAssertEqual(surface.topBar.memoryLabel, "No memories")
        XCTAssertEqual(surface.topBar.memorySources, [])
        XCTAssertEqual(surface.projects.items.count, 1)
        XCTAssertEqual(surface.projects.items[0].name, "QuillCode")
        XCTAssertEqual(surface.projects.items[0].path, "/tmp/QuillCode")
        XCTAssertTrue(surface.projects.items[0].isSelected)
        XCTAssertEqual(surface.projects.items[0].actions.map(\.kind), [.newChat, .refreshContext, .rename, .remove])
        XCTAssertEqual(surface.sidebar.items.count, 1)
        XCTAssertEqual(surface.sidebar.items[0].title, "Run whoami")
        XCTAssertTrue(surface.sidebar.items[0].isSelected)
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
            "fork-from-last",
            "compact-context",
            "retry-last-turn",
            "search",
            "find-in-chat",
            "add-project",
            "project-new-chat",
            "project-refresh-context",
            "project-rename",
            "project-remove",
            "toggle-terminal",
            "toggle-browser",
            "toggle-memories",
            "memory-add",
            "toggle-extensions",
            "git-pr-create",
            "git-worktree-list",
            "git-worktree-create",
            "git-worktree-remove",
            "stop-all",
            "settings",
            "command-palette",
            "computer-use-setup"
        ])
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "find-in-chat" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.settings.apiBaseURL, TrustedRouterDefaults.defaultAPIBaseURL)
        XCTAssertFalse(surface.settings.developerOverrideEnabled)
        XCTAssertFalse(surface.settings.hasStoredAPIKey)
        XCTAssertEqual(surface.settings.authMode, .oauth)
        XCTAssertEqual(surface.settings.signInURL, TrustedRouterDefaults.loopbackCallbackURL)
        XCTAssertEqual(surface.settings.apiKeyStatusLabel, "Not signed in")
        XCTAssertFalse(surface.terminal.isVisible)
        XCTAssertEqual(surface.terminal.cwdLabel, "/tmp/QuillCode")
        XCTAssertFalse(surface.browser.isVisible)
        XCTAssertFalse(surface.extensions.isVisible)
        XCTAssertFalse(surface.memories.isVisible)
    }

    func testComposerShowsFilteredSlashSuggestions() {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/")
        var suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.prefix(3).map(\.usage), ["/help", "/status", "/new"])

        model.setDraft("/wor")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/worktrees")
        XCTAssertEqual(suggestions.first?.insertText, "/worktrees")

        model.setDraft("/project r")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.prefix(2).map(\.usage), ["/project refresh", "/project rename name"])

        model.setDraft("run /help")
        XCTAssertEqual(model.surface().composer.slashSuggestions, [])
    }

    func testSettingsSurfaceShowsTrustedRouterAccount() {
        let config = AppConfig(
            authMode: .oauth,
            trustedRouterAccount: TrustedRouterAccountProfile(
                userID: "usr_123",
                email: "quill@example.com"
            )
        )
        let settings = WorkspaceSettingsSurface(config: config, hasStoredAPIKey: true)

        XCTAssertEqual(settings.apiKeyStatusLabel, "Signed in")
        XCTAssertEqual(settings.loginStatusLabel, "Signed in as quill@example.com")
        XCTAssertEqual(settings.accountLabel, "quill@example.com")
    }

    func testRuntimeIssueDecodesOlderPayloadWithoutDiagnostics() throws {
        let data = """
        {
          "severity": "warning",
          "title": "Old issue",
          "message": "Older renderer payload",
          "actionLabel": "Retry"
        }
        """.data(using: .utf8)!

        let issue = try JSONDecoder().decode(RuntimeIssueSurface.self, from: data)

        XCTAssertEqual(issue.title, "Old issue")
        XCTAssertEqual(issue.actionLabel, "Retry")
        XCTAssertTrue(issue.diagnostics.isEmpty)
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
            WorkspaceCommandPalette.rankedCommands(commands, matching: "pull").first?.id,
            "git-pr-create"
        )
    }

    func testCommandPaletteGroupsFilteredResultsByCategory() {
        let model = QuillCodeWorkspaceModel()
        let groups = WorkspaceCommandPalette.groupedCommands(model.surface().commands, matching: "worktree")

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

    func testSurfaceGroupsCustomModelCatalogByCategory() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "acme/code-pro"),
            topBar: TopBarState(model: "acme/code-pro")
        ))
        model.setModelCatalog([
            .init(id: "trustedrouter/fusion", provider: "trustedrouter", displayName: "Fusion", category: "Recommended"),
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "acme/fast", provider: "acme", displayName: "Fast", category: "Coding")
        ])

        let surface = model.surface()

        XCTAssertEqual(surface.topBar.modelLabel, "acme/Code Pro")
        XCTAssertEqual(surface.topBar.modelCategories.map(\.category), ["Recommended", "Coding"])
        let coding = surface.topBar.modelCategories.first { $0.category == "Coding" }
        XCTAssertEqual(coding?.models.map(\.id), ["acme/code-pro", "acme/fast"])
        XCTAssertTrue(coding?.models.first?.isSelected == true)
    }

    func testTopBarFiltersModelCatalogByProviderCategoryAndModel() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "trustedrouter/fusion"),
            topBar: TopBarState(model: "trustedrouter/fusion")
        ))
        model.setModelCatalog([
            .init(id: "trustedrouter/fusion", provider: "trustedrouter", displayName: "Fusion", category: "Recommended"),
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "moonshotai/kimi-k2.6", provider: "moonshotai", displayName: "Kimi K2.6", category: "Safety")
        ])

        let topBar = model.surface().topBar

        XCTAssertEqual(topBar.filteredModelCategories(matching: "coding").flatMap(\.models).map(\.id), ["acme/code-pro"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "moon k2").flatMap(\.models).map(\.id), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "trusted fusion").flatMap(\.models).map(\.id), ["trustedrouter/fusion"])
        XCTAssertTrue(topBar.filteredModelCategories(matching: "does-not-exist").isEmpty)
    }

    func testSurfaceIncludesLocalEnvironmentActionCommands() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            localActions: [
                LocalEnvironmentAction(
                    id: "local-env:.quillcode/actions/bootstrap.sh",
                    title: "Bootstrap",
                    relativePath: ".quillcode/actions/bootstrap.sh",
                    command: "sh '.quillcode/actions/bootstrap.sh'"
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
                    relativePath: ".quillcode/plugins/github.json"
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
                        toolNames: ["read_file", "write_file"]
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

    func testSurfaceIncludesBrowserPreviewState() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.toggleBrowser()
        XCTAssertTrue(model.openBrowserPreview("example.com", workspaceRoot: root))
        XCTAssertTrue(model.addBrowserComment("Looks aligned"))

        let surface = model.surface()

        XCTAssertTrue(surface.browser.isVisible)
        XCTAssertEqual(surface.browser.currentURL, "https://example.com")
        XCTAssertEqual(surface.browser.title, "example.com")
        XCTAssertEqual(surface.browser.statusLabel, "Comment added")
        XCTAssertEqual(surface.browser.snapshot?.sourceLabel, "Web page")
        XCTAssertEqual(surface.browser.snapshot?.summary, "Ready to open in the browser preview.")
        XCTAssertEqual(surface.browser.snapshot?.details, [
            "Host: example.com",
            "Scheme: HTTPS",
            "Path: /"
        ])
        XCTAssertEqual(surface.browser.comments.first?.text, "Looks aligned")
        XCTAssertTrue(surface.browser.canOpen)
        XCTAssertTrue(surface.commands.contains { $0.id == "toggle-browser" && $0.title == "Browser" })
    }

    func testSurfaceKeepsUnknownSelectedModelVisible() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "custom/edge-model"),
            topBar: TopBarState(model: "custom/edge-model"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let surface = model.surface()
        let current = surface.topBar.modelCategories.first { $0.category == "Current" }

        XCTAssertEqual(surface.topBar.modelLabel, "custom/edge-model")
        XCTAssertEqual(current?.models.first?.id, "custom/edge-model")
        XCTAssertEqual(current?.models.first?.displayName, "edge-model")
        XCTAssertTrue(current?.models.first?.isSelected == true)
    }

    func testModelPickerShowsRecentModelsAndBadges() throws {
        let older = ChatThread(
            title: "Older model",
            model: "z-ai/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ChatThread(
            title: "Newer model",
            model: "moonshotai/kimi-k2.6",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "trustedrouter/fusion"),
            threads: [older, newer],
            selectedThreadID: newer.id,
            topBar: TopBarState(model: "moonshotai/kimi-k2.6"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let topBar = model.surface().topBar
        let recent = try XCTUnwrap(topBar.modelCategories.first)

        XCTAssertEqual(recent.category, "Recent")
        XCTAssertEqual(recent.models.map(\.id), ["moonshotai/kimi-k2.6", "z-ai/glm-5.2"])
        XCTAssertEqual(recent.models.first?.badges, ["Recent", "Current"])

        let defaultOption = try XCTUnwrap(topBar.modelCategories
            .flatMap(\.models)
            .first { $0.id == "trustedrouter/fusion" })
        XCTAssertTrue(defaultOption.badges.contains("Default"))
        XCTAssertTrue(defaultOption.badges.contains("Recommended"))

        XCTAssertEqual(topBar.filteredModelCategories(matching: "moon k2").flatMap(\.models).map(\.id), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "recent").first?.category, "Recent")
    }

    func testModelPickerShowsFavoriteModelsBeforeRecent() throws {
        let older = ChatThread(
            title: "Favorite model",
            model: "z-ai/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ChatThread(
            title: "Recent model",
            model: "moonshotai/kimi-k2.6",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(
                defaultModel: "trustedrouter/fusion",
                favoriteModels: [" z-ai/glm-5.2 ", "z-ai/glm-5.2"]
            ),
            threads: [older, newer],
            selectedThreadID: newer.id,
            topBar: TopBarState(model: "moonshotai/kimi-k2.6"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let topBar = model.surface().topBar
        XCTAssertEqual(topBar.modelCategories.prefix(2).map(\.category), ["Favorites", "Recent"])

        let favorite = try XCTUnwrap(topBar.modelCategories.first)
        XCTAssertEqual(favorite.models.map(\.id), ["z-ai/glm-5.2"])
        XCTAssertTrue(favorite.models.first?.isFavorite == true)
        XCTAssertEqual(favorite.models.first?.badges, ["Favorite"])

        let recent = try XCTUnwrap(topBar.modelCategories.dropFirst().first)
        XCTAssertEqual(recent.models.map(\.id), ["moonshotai/kimi-k2.6"])

        XCTAssertEqual(topBar.filteredModelCategories(matching: "favorite").map(\.category), ["Favorites"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "glm").flatMap(\.models).map(\.id), ["z-ai/glm-5.2"])
    }

    func testModelOptionDecodesOlderPayloadWithoutBadges() throws {
        let data = """
        {
          "id": "trustedrouter/fusion",
          "provider": "trustedrouter",
          "displayName": "Fusion",
          "category": "Recommended",
          "isSelected": true
        }
        """.data(using: .utf8)!

        let option = try JSONDecoder().decode(ModelOptionSurface.self, from: data)

        XCTAssertEqual(option.id, "trustedrouter/fusion")
        XCTAssertTrue(option.isSelected)
        XCTAssertFalse(option.isFavorite)
        XCTAssertTrue(option.badges.isEmpty)
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
        let selectedThread = ChatThread(title: "Run whoami", model: "trustedrouter/fusion")
        var otherThread = ChatThread(title: "Review git diff", model: "z-ai/glm-5.2", isPinned: true)
        otherThread.messages = [
            .init(role: .user, content: "Can you inspect the browser preview?")
        ]
        var archivedThread = ChatThread(title: "Old release plan", model: "trustedrouter/fusion")
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

    func testHTMLRendererEscapesAndLabelsPrimaryRegions() {
        let project = ProjectRef(
            name: "Unsafe <project>",
            path: "/tmp/unsafe",
            lastOpenedAt: Date(),
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: "Project AGENTS.md",
                    content: "No <script> tags.",
                    byteCount: 17
                )
            ]
        )
        var thread = ChatThread(title: "Unsafe <title>")
        thread.messages = [
            .init(role: .user, content: "<script>alert(1)</script>")
        ]
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="top-bar""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar""#))
        XCTAssertTrue(html.contains(#"data-testid="add-project-button""#))
        XCTAssertTrue(html.contains(#"data-testid="project-item""#))
        XCTAssertTrue(html.contains(#"data-testid="transcript""#))
        XCTAssertTrue(html.contains(#"data-testid="composer""#))
        XCTAssertTrue(html.contains(#"data-testid="project-instructions-status""#))
        XCTAssertTrue(html.contains("1 instruction file loaded"))
        XCTAssertTrue(html.contains("AGENTS.md"))
        XCTAssertTrue(html.contains("Unsafe &lt;title&gt;"))
        XCTAssertTrue(html.contains("Unsafe &lt;project&gt;"))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
    }

    func testHTMLRendererShowsStopButtonDuringActiveSend() {
        let model = QuillCodeWorkspaceModel(composer: ComposerState(isSending: true))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="stop-button""#))
        XCTAssertTrue(html.contains(">Stop</button>"))
        XCTAssertTrue(html.contains(#"id="message" aria-label="Message""#))
        XCTAssertTrue(html.contains("disabled"))
        XCTAssertFalse(html.contains(#"data-testid="send-button""#))
    }

    func testHTMLRendererIncludesContextBanner() throws {
        let thread = ChatThread(title: "Long context", messages: [
            .init(role: .user, content: String(repeating: "token ", count: 26_000))
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="context-banner""#))
        XCTAssertTrue(html.contains(#"data-testid="context-new-thread""#))
        XCTAssertTrue(html.contains(#"data-testid="context-fork-last""#))
        XCTAssertTrue(html.contains(#"data-testid="context-compact""#))
    }

    func testHTMLRendererIncludesRuntimeIssue() throws {
        let model = QuillCodeWorkspaceModel()
        model.setAgentStatus("Failed", lastError: "TrustedRouter returned an empty response.")

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="runtime-issue""#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-issue-pill""#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-issue-title">TrustedRouter returned no content"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-issue-action">Retry"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostics""#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-label">API base URL"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-label">Last error"#))
    }

    func testHTMLRendererGroupsPinnedRecentAndArchivedChats() {
        var pinned = ChatThread(title: "Pinned chat", model: "trustedrouter/fusion")
        pinned.isPinned = true
        let recent = ChatThread(title: "Recent chat", model: "z-ai/glm-5.2")
        var archived = ChatThread(title: "Archived chat", model: "trustedrouter/fusion")
        archived.isArchived = true
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [recent, pinned, archived],
            selectedThreadID: recent.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Pinned"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Recent"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Archived"#))
        XCTAssertTrue(html.contains("Pinned chat"))
        XCTAssertTrue(html.contains("Recent chat"))
        XCTAssertTrue(html.contains("Archived chat"))
    }

    func testHTMLRendererIncludesToolCardOutput() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card""#))
        XCTAssertTrue(html.contains(#"data-status="done""#))
        XCTAssertTrue(html.contains("host.shell.run"))
        XCTAssertTrue(html.contains(#"data-testid="message-copy""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-copy""#))
        XCTAssertTrue(html.contains("Copy output"))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-output""#))
    }

    func testHTMLRendererIncludesToolCardArtifacts() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifacts""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact-label""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact-detail""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-details""#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-details" open"#))
        XCTAssertTrue(html.contains(#"data-kind="file""#))
        XCTAssertTrue(html.contains("hello.txt"))
    }

    func testHTMLRendererKeepsToolCardsInTranscriptOrder() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())
        let userIndex = try XCTUnwrap(html.range(of: "run whoami")?.lowerBound)
        let toolIndex = try XCTUnwrap(html.range(of: "host.shell.run")?.lowerBound)
        let answerIndex = try XCTUnwrap(html.range(of: "You are `")?.lowerBound)

        XCTAssertLessThan(userIndex, toolIndex)
        XCTAssertLessThan(toolIndex, answerIndex)
    }

    func testHTMLRendererIncludesVisibleTerminalPane() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.toggleTerminal()
        await model.runTerminalCommand("printf renderer-ok", workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="terminal-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="terminal-cwd""#))
        XCTAssertTrue(html.contains(#"data-testid="terminal-entry""#))
        XCTAssertTrue(html.contains("renderer-ok"))
    }

    func testHTMLRendererIncludesVisibleBrowserPane() throws {
        let model = QuillCodeWorkspaceModel()
        model.toggleBrowser()
        XCTAssertTrue(model.openBrowserPreview("localhost:5173"))
        XCTAssertTrue(model.addBrowserComment("Inspect responsive state"))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="browser-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-current-url""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-snapshot""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-source""#))
        XCTAssertTrue(html.contains("Local web app"))
        XCTAssertTrue(html.contains("http://localhost:5173"))
        XCTAssertTrue(html.contains(#"data-testid="browser-comment""#))
        XCTAssertTrue(html.contains("Inspect responsive state"))
    }

    func testHTMLRendererIncludesVisibleExtensionsPane() throws {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
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

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="extensions-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-item""#))
        XCTAssertTrue(html.contains("Filesystem MCP"))
        XCTAssertTrue(html.contains(#"data-testid="extension-transport""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-start""#))
        XCTAssertTrue(html.contains(".quillcode/mcp/filesystem.json"))
    }

    func testHTMLRendererIncludesVisibleMemoriesPane() throws {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            memories: [
                MemoryNote(
                    id: "project:.quillcode/memories/project.md",
                    scope: .project,
                    title: "Project",
                    content: "Use SwiftUI surfaces for visible state.",
                    relativePath: ".quillcode/memories/project.md",
                    byteCount: 38
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            memories: MemoriesState(isVisible: true)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="memories-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="memory-item""#))
        XCTAssertTrue(html.contains("Project"))
        XCTAssertTrue(html.contains(".quillcode/memories/project.md"))
    }

    func testHTMLRendererIncludesGitReviewPane() throws {
        let diff = """
        diff --git a/Package.swift b/Package.swift
        --- a/Package.swift
        +++ b/Package.swift
        @@ -1 +1,2 @@
        +// QuillCode
         import PackageDescription
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let comment = WorkspaceReviewCommentState(path: "Package.swift", text: "Confirm package tools version.")
        let thread = ChatThread(
            title: "Git diff",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Package.swift", payloadJSON: try JSONHelpers.encodePretty(comment))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="review-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="review-file""#))
        XCTAssertTrue(html.contains(#"data-testid="review-action""#))
        XCTAssertTrue(html.contains(#"data-testid="review-hunk""#))
        XCTAssertTrue(html.contains(#"data-testid="review-line""#))
        XCTAssertTrue(html.contains(#"data-testid="review-comment""#))
        XCTAssertTrue(html.contains(#"data-action="stage""#))
        XCTAssertTrue(html.contains(#"data-action="restore""#))
        XCTAssertTrue(html.contains(#"data-action="stage_hunk""#))
        XCTAssertTrue(html.contains(#"data-action="restore_hunk""#))
        XCTAssertTrue(html.contains("Package.swift"))
        XCTAssertTrue(html.contains("Confirm package tools version."))
        XCTAssertTrue(html.contains("Stage"))
        XCTAssertTrue(html.contains("Restore"))
        XCTAssertTrue(html.contains("1 file changed, +1 -0"))
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeSurfaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
