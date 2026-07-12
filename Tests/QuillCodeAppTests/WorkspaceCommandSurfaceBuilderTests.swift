import XCTest
import QuillCodeCore
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceCommandSurfaceBuilderTests: XCTestCase {
    func testCommandSurfaceDecodesOlderPayloadWithoutCategoryMetadata() throws {
        let data = #"{"id":"search","title":"Search","shortcut":"Cmd+K","isEnabled":true}"#.data(using: .utf8)!

        let command = try JSONDecoder().decode(WorkspaceCommandSurface.self, from: data)

        XCTAssertEqual(command.category, WorkspaceCommandPalette.workspaceCategory)
        XCTAssertEqual(command.keywords, [])
    }

    func testDefaultCommandsUseConservativeAvailability() throws {
        let commands = makeBuilder().commands

        XCTAssertEqual(try command("new-chat", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-rename", in: commands).isEnabled, false)
        XCTAssertEqual(try command("thread-clear", in: commands).isEnabled, false)
        XCTAssertEqual(try command("workspace-back", in: commands).isEnabled, false)
        XCTAssertEqual(try command("workspace-forward", in: commands).isEnabled, false)
        XCTAssertEqual(try command("find-in-chat", in: commands).isEnabled, false)
        XCTAssertEqual(try command("copy-conversation", in: commands).shortcut, "Cmd+Shift+C")
        XCTAssertEqual(try command("copy-conversation", in: commands).isEnabled, false)
        XCTAssertEqual(try command("toggle-sidebar", in: commands).isEnabled, true)
        XCTAssertEqual(try command("project-new-chat", in: commands).isEnabled, false)
        XCTAssertEqual(try command("project-move-to-top", in: commands).isEnabled, false)
        XCTAssertEqual(try command("project-move-up", in: commands).isEnabled, false)
        XCTAssertEqual(try command("project-move-down", in: commands).isEnabled, false)
        XCTAssertEqual(try command("project-move-to-bottom", in: commands).isEnabled, false)
        XCTAssertEqual(try command("show-skills", in: commands).isEnabled, false)
        XCTAssertEqual(try command("git-status", in: commands).isEnabled, false)
        XCTAssertEqual(try command("git-fetch", in: commands).isEnabled, false)
        XCTAssertEqual(try command("git-pull", in: commands).isEnabled, false)
        XCTAssertEqual(try command("terminal-clear", in: commands).isEnabled, false)
        XCTAssertEqual(try command("open-browser-session", in: commands).isEnabled, false)
        XCTAssertEqual(try command("stop-all", in: commands).isEnabled, false)
        XCTAssertEqual(try command("disconnect-all", in: commands).isEnabled, false)
        XCTAssertEqual(try command("computer-use-setup", in: commands).isEnabled, true)
        XCTAssertEqual(try command("computer-use-open-screen-recording", in: commands).isEnabled, true)
        XCTAssertEqual(try command("computer-use-open-accessibility", in: commands).isEnabled, true)
    }

    func testWorkspaceNavigationAvailabilityUsesHistoryFlags() throws {
        let commands = makeBuilder(canNavigateBack: true, canNavigateForward: true).commands

        XCTAssertEqual(try command("workspace-back", in: commands).isEnabled, true)
        XCTAssertEqual(try command("workspace-forward", in: commands).isEnabled, true)
        XCTAssertEqual(try command("workspace-back", in: commands).category, WorkspaceCommandPalette.navigationCategory)
        XCTAssertEqual(try command("workspace-forward", in: commands).category, WorkspaceCommandPalette.navigationCategory)
        XCTAssertEqual(try command("workspace-back", in: commands).shortcut, "Cmd+Option+←")
        XCTAssertEqual(try command("workspace-forward", in: commands).shortcut, "Cmd+Option+→")
    }

    func testCommandOrderingPreservesHighPriorityPaletteSequence() throws {
        let action = LocalEnvironmentAction(
            id: "local-env:.quillcode/actions/bootstrap.sh",
            title: "Bootstrap",
            relativePath: ".quillcode/actions/bootstrap.sh",
            command: "sh .quillcode/actions/bootstrap.sh"
        )
        let mcpManifest = ProjectExtensionManifest(
            id: "mcp_server:filesystem",
            kind: .mcpServer,
            name: "Filesystem MCP",
            relativePath: ".quillcode/mcp/filesystem.json",
            launchExecutable: "quill-mcp",
            installCommand: "quill-mcp install",
            updateCommand: "quill-mcp update"
        )
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            localActions: [action],
            extensionManifests: [mcpManifest]
        )
        let commandIDs = makeBuilder(
            selectedThread: ChatThread(messages: [.init(role: .user, content: "Run tests")]),
            selectedProject: project,
            hasActiveWorkspaceRoot: true,
            canRetryLastUserTurn: true
        ).commands.map(\.id)

        XCTAssertLessThan(index(of: "retry-last-turn", in: commandIDs), index(of: "workspace-back", in: commandIDs))
        XCTAssertLessThan(index(of: "workspace-forward", in: commandIDs), index(of: "search", in: commandIDs))
        XCTAssertLessThan(index(of: "toggle-extensions", in: commandIDs), index(of: "git-status", in: commandIDs))
        XCTAssertLessThan(index(of: "git-status", in: commandIDs), index(of: "git-fetch", in: commandIDs))
        XCTAssertLessThan(index(of: "git-fetch", in: commandIDs), index(of: "git-pull", in: commandIDs))
        XCTAssertLessThan(index(of: "git-worktree-remove", in: commandIDs), index(of: "git-worktree-prune", in: commandIDs))
        XCTAssertLessThan(index(of: "git-worktree-prune", in: commandIDs), index(of: "local-env:.quillcode/actions/bootstrap.sh", in: commandIDs))
        XCTAssertLessThan(index(of: "local-env:.quillcode/actions/bootstrap.sh", in: commandIDs), index(of: "mcp-start:mcp_server:filesystem", in: commandIDs))
        XCTAssertLessThan(index(of: "mcp-stop:mcp_server:filesystem", in: commandIDs), index(of: "extension-install:mcp_server:filesystem", in: commandIDs))
        XCTAssertLessThan(index(of: "extension-install:mcp_server:filesystem", in: commandIDs), index(of: "extension-update:mcp_server:filesystem", in: commandIDs))
        XCTAssertLessThan(index(of: "extension-update:mcp_server:filesystem", in: commandIDs), index(of: "stop-all", in: commandIDs))
    }

    func testSelectedThreadAndSidebarSelectionEnableThreadCommands() throws {
        let selectedThread = ChatThread(messages: [.init(role: .user, content: "Run whoami")])
        let unpinnedThread = ChatThread(title: "Unpinned")
        let pinnedThread = ChatThread(title: "Pinned", isPinned: true)
        let archivedThread = ChatThread(title: "Archived", isArchived: true)
        let commands = makeBuilder(
            selectedThread: selectedThread,
            selectedSidebarThreads: [unpinnedThread, pinnedThread, archivedThread],
            sidebarSelectionIsActive: true,
            sidebarItemCount: 3,
            canRetryLastUserTurn: true
        ).commands

        XCTAssertEqual(try command("thread-rename", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-pin", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-unpin", in: commands).isEnabled, false)
        XCTAssertEqual(try command("thread-clear", in: commands).isEnabled, true)
        XCTAssertEqual(try command("fork-from-last", in: commands).isEnabled, true)
        XCTAssertEqual(try command("fork-with-summary", in: commands).isEnabled, true)
        XCTAssertEqual(try command("fork-full-context", in: commands).isEnabled, true)
        XCTAssertEqual(try command("compact-context", in: commands).isEnabled, true)
        XCTAssertEqual(try command("find-in-chat", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-selection-clear", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-pin", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-unpin", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-archive", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-unarchive", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-delete", in: commands).isEnabled, true)
        XCTAssertEqual(try command("retry-last-turn", in: commands).isEnabled, true)

        var pinnedSelectedThread = selectedThread
        pinnedSelectedThread.isPinned = true
        let pinnedCommands = makeBuilder(selectedThread: pinnedSelectedThread).commands
        XCTAssertEqual(try command("thread-pin", in: pinnedCommands).isEnabled, false)
        XCTAssertEqual(try command("thread-unpin", in: pinnedCommands).isEnabled, true)

        var archivedSelectedThread = selectedThread
        archivedSelectedThread.isArchived = true
        let archivedCommands = makeBuilder(selectedThread: archivedSelectedThread).commands
        XCTAssertEqual(try command("thread-pin", in: archivedCommands).isEnabled, false)
        XCTAssertEqual(try command("thread-unpin", in: archivedCommands).isEnabled, false)
    }

    func testThreadClearCommandIsEnabledForEventOnlyThread() throws {
        let selectedThread = ChatThread(
            events: [.init(kind: .toolCompleted, summary: "Ran shell")]
        )
        let commands = makeBuilder(selectedThread: selectedThread).commands

        XCTAssertEqual(try command("thread-clear", in: commands).isEnabled, true)
        XCTAssertEqual(try command("compact-context", in: commands).isEnabled, false)
    }

    func testRunningThreadDisablesContextReplacingAndDestructiveCommands() throws {
        let selectedThread = ChatThread(messages: [.init(role: .user, content: "Run tests")])
        let commands = makeBuilder(
            selectedThread: selectedThread,
            selectedThreadIsRunning: true,
            runningThreadIDs: [selectedThread.id]
        ).commands

        for commandID in [
            "thread-duplicate",
            "thread-clear",
            "thread-revert-latest",
            "thread-delete",
            "fork-from-last",
            "fork-with-summary",
            "fork-full-context",
            "compact-context"
        ] {
            XCTAssertFalse(try command(commandID, in: commands).isEnabled, commandID)
        }
        XCTAssertTrue(try command("thread-rename", in: commands).isEnabled)
        XCTAssertTrue(try command("thread-archive", in: commands).isEnabled)
    }

    func testBulkDeleteDisablesWhenSelectedChatsIncludeARunningThread() throws {
        let running = ChatThread(title: "Running")
        let idle = ChatThread(title: "Idle")
        let commands = makeBuilder(
            selectedThread: idle,
            selectedSidebarThreads: [running, idle],
            sidebarSelectionIsActive: true,
            sidebarItemCount: 2,
            runningThreadIDs: [running.id]
        ).commands

        XCTAssertFalse(try command("thread-bulk-delete", in: commands).isEnabled)
        XCTAssertTrue(try command("thread-bulk-archive", in: commands).isEnabled)
    }

    func testHandoffCommandNamesDestinationAndRequiresIdleDetachedManagedTask() throws {
        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktree) }
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        var thread = ChatThread(title: "Managed task")
        thread.worktree = WorktreeBinding(
            path: worktree.path,
            branch: "",
            base: "main",
            location: .worktree
        )

        let worktreeCommand = try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        )
        XCTAssertEqual(worktreeCommand.title, "Hand off to Local")
        XCTAssertTrue(worktreeCommand.isEnabled)

        thread.worktree?.location = .local
        let localCommand = try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        )
        XCTAssertEqual(localCommand.title, "Hand off to Worktree")
        XCTAssertTrue(localCommand.isEnabled)

        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(
                selectedThread: thread,
                selectedProject: project,
                composerIsSending: true
            ).commands
        ).isEnabled)
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(
                selectedThread: thread,
                selectedProject: project,
                selectedThreadIsRunning: true,
                runningThreadIDs: [thread.id]
            ).commands
        ).isEnabled)
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(
                selectedThread: thread,
                selectedProject: project,
                terminalIsRunning: true
            ).commands
        ).isEnabled)

        thread.worktree?.branch = "feature/owned"
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        ).isEnabled)

        thread.worktree?.branch = ""
        thread.isArchived = true
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        ).isEnabled)

        thread.isArchived = false
        let remoteProject = ProjectRef(
            name: "Remote",
            path: "/srv/quill",
            connection: .ssh(path: "/srv/quill", host: "quill.local", user: "quill")
        )
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: remoteProject).commands
        ).isEnabled)

        thread.worktree?.path = worktree.path + "-missing"
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadHandoff.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        ).isEnabled)
    }

    func testCreateBranchCommandRequiresIdleDetachedWorktreeTask() throws {
        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("create-branch-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktree) }
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        var thread = ChatThread(title: "Detached task")
        thread.worktree = WorktreeBinding(
            path: worktree.path,
            branch: "",
            base: "main",
            location: .worktree
        )

        XCTAssertTrue(try command(
            WorkspaceCommandAction.threadCreateBranch.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        ).isEnabled)

        thread.worktree?.location = .local
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadCreateBranch.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        ).isEnabled)

        thread.worktree?.location = .worktree
        thread.worktree?.branch = "feature/owned"
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadCreateBranch.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        ).isEnabled)

        thread.worktree?.branch = ""
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadCreateBranch.rawValue,
            in: makeBuilder(
                selectedThread: thread,
                selectedProject: project,
                selectedThreadIsRunning: true,
                runningThreadIDs: [thread.id]
            ).commands
        ).isEnabled)

        thread.worktree?.path = worktree.path + "-missing"
        XCTAssertFalse(try command(
            WorkspaceCommandAction.threadCreateBranch.rawValue,
            in: makeBuilder(selectedThread: thread, selectedProject: project).commands
        ).isEnabled)
    }

    func testSavedSearchesAppearAsThreadCommands() throws {
        let searchID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let secondSearchID = try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let commands = makeBuilder(
            sidebarSavedSearches: [
                SidebarSavedSearch(id: searchID, title: "Failures", query: "failed error"),
                SidebarSavedSearch(id: secondSearchID, title: "OpenClaw", query: "openclaw"),
                SidebarSavedSearch(title: "", query: "hidden")
            ]
        ).commands

        let savedSearch = try command("sidebar-saved-search:\(searchID.uuidString)", in: commands)
        XCTAssertEqual(savedSearch.title, "Show Failures")
        XCTAssertEqual(savedSearch.category, WorkspaceCommandPalette.threadCategory)
        XCTAssertTrue(savedSearch.keywords.contains("saved search"))
        XCTAssertTrue(savedSearch.keywords.contains("failed error"))
        let deleteSavedSearch = try command("sidebar-saved-search-delete:\(searchID.uuidString)", in: commands)
        XCTAssertEqual(deleteSavedSearch.title, "Delete saved search Failures")
        XCTAssertTrue(deleteSavedSearch.keywords.contains("delete"))
        XCTAssertEqual(
            try command("sidebar-saved-search-move-up:\(searchID.uuidString)", in: commands).isEnabled,
            false
        )
        XCTAssertEqual(
            try command("sidebar-saved-search-move-down:\(searchID.uuidString)", in: commands).isEnabled,
            true
        )
        XCTAssertEqual(
            try command("sidebar-saved-search-move-up:\(secondSearchID.uuidString)", in: commands).isEnabled,
            true
        )
        XCTAssertEqual(
            try command("sidebar-saved-search-move-down:\(secondSearchID.uuidString)", in: commands).isEnabled,
            false
        )
        XCTAssertNotNil(commands.first { $0.id == "sidebar-saved-search-create" })
        XCTAssertFalse(commands.contains { $0.title == "Show hidden" })
    }

    func testProjectActionsMCPAndGitCommandsUseProjectContext() throws {
        let action = LocalEnvironmentAction(
            id: "local-env:.quillcode/actions/bootstrap.sh",
            title: "Bootstrap",
            detail: "Install dependencies.",
            relativePath: ".quillcode/actions/bootstrap.sh",
            command: "sh .quillcode/actions/bootstrap.sh",
            environment: ["QUILL_ENV": "dev"],
            workingDirectory: "app",
            timeoutSeconds: 90
        )
        let updateManifest = ProjectExtensionManifest(
            id: "plugin:github",
            kind: .plugin,
            name: "GitHub",
            summary: "PR workflow helpers.",
            version: "1.2.0",
            sourceURL: "https://github.com/Lore-Hex/quillcode-github",
            relativePath: ".quillcode/plugins/github.json",
            installCommand: "git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github",
            updateCommand: "git pull --ff-only"
        )
        let mcpManifest = ProjectExtensionManifest(
            id: "mcp_server:filesystem",
            kind: .mcpServer,
            name: "Filesystem MCP",
            relativePath: ".quillcode/mcp/filesystem.json",
            launchExecutable: "quill-mcp"
        )
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            localActions: [action],
            extensionManifests: [updateManifest, mcpManifest]
        )
        let commands = makeBuilder(
            selectedProject: project,
            hasActiveWorkspaceRoot: true,
            mcpServerStatuses: ["mcp_server:filesystem": .ready],
            mcpServerProbeSummaries: [
                "mcp_server:filesystem": MCPServerProbeSummary(
                    resourceNames: ["README"],
                    resourceURIs: ["file:///workspace/README.md"],
                    promptNames: ["summarize_project"]
                )
            ]
        ).commands

        let localAction = try command("local-env:.quillcode/actions/bootstrap.sh", in: commands)
        XCTAssertEqual(localAction.title, "Run Bootstrap")
        XCTAssertEqual(localAction.category, WorkspaceCommandPalette.environmentCategory)
        XCTAssertEqual(localAction.isEnabled, true)
        XCTAssertTrue(localAction.keywords.contains("Install dependencies."))
        XCTAssertTrue(localAction.keywords.contains("QUILL_ENV"))
        XCTAssertTrue(localAction.keywords.contains("app"))
        XCTAssertTrue(localAction.keywords.contains("90s"))

        XCTAssertEqual(try command("project-new-chat", in: commands).isEnabled, true)
        XCTAssertEqual(try command("project-move-to-top", in: commands).isEnabled, true)
        XCTAssertEqual(try command("project-move-up", in: commands).isEnabled, true)
        XCTAssertEqual(try command("project-move-down", in: commands).isEnabled, true)
        XCTAssertEqual(try command("project-move-to-bottom", in: commands).isEnabled, true)
        XCTAssertEqual(try command("toggle-extensions", in: commands).isEnabled, true)
        XCTAssertEqual(try command("show-skills", in: commands).isEnabled, true)
        XCTAssertEqual(try command("git-status", in: commands).isEnabled, true)
        XCTAssertEqual(try command("extension-install:plugin:github", in: commands).isEnabled, true)
        XCTAssertEqual(try command("extension-update:plugin:github", in: commands).isEnabled, true)
        XCTAssertTrue(try command("extension-install:plugin:github", in: commands).keywords.contains("PR workflow helpers."))
        XCTAssertEqual(try command("mcp-start:mcp_server:filesystem", in: commands).isEnabled, false)
        XCTAssertEqual(try command("mcp-stop:mcp_server:filesystem", in: commands).isEnabled, true)
        XCTAssertEqual(try command("mcp-resource:mcp_server:filesystem:0", in: commands).title, "Read README")
        XCTAssertEqual(try command("mcp-resource:mcp_server:filesystem:0", in: commands).isEnabled, true)
        XCTAssertEqual(try command("mcp-prompt:mcp_server:filesystem:0", in: commands).title, "Use summarize_project")
        XCTAssertEqual(try command("mcp-prompt:mcp_server:filesystem:0", in: commands).isEnabled, true)
        XCTAssertEqual(try command("stop-all", in: commands).isEnabled, true)
        XCTAssertEqual(try command("disconnect-all", in: commands).isEnabled, true)
    }

    func testSelectedRemoteProjectEnablesDisconnectAllWithoutActiveWork() throws {
        let connection = ProjectConnection.ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let commands = makeBuilder(
            selectedProject: project,
            hasActiveWorkspaceRoot: true
        ).commands

        XCTAssertEqual(try command("stop-all", in: commands).isEnabled, false)
        XCTAssertEqual(try command("disconnect-all", in: commands).isEnabled, true)
    }

    func testBrowserTerminalAndComputerUseCommandsReflectRuntimeState() throws {
        let readyComputerUse = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: true
        )
        let commands = makeBuilder(
            composerIsSending: true,
            terminalHasEntries: true,
            terminalIsRunning: false,
            browserCanGoBack: true,
            browserCanGoForward: true,
            browserCanReload: true,
            browserCanOpenSession: true,
            computerUseStatus: readyComputerUse
        ).commands

        XCTAssertEqual(try command("terminal-clear", in: commands).isEnabled, true)
        XCTAssertEqual(try command("browser-back", in: commands).isEnabled, true)
        XCTAssertEqual(try command("browser-forward", in: commands).isEnabled, true)
        XCTAssertEqual(try command("browser-reload", in: commands).isEnabled, true)
        XCTAssertEqual(try command("open-browser-session", in: commands).isEnabled, true)
        XCTAssertEqual(try command("stop-all", in: commands).isEnabled, true)
        XCTAssertEqual(try command("computer-use-setup", in: commands).isEnabled, false)
        XCTAssertEqual(try command("computer-use-open-screen-recording", in: commands).isEnabled, false)
        XCTAssertEqual(try command("computer-use-open-accessibility", in: commands).isEnabled, false)
    }

    private func makeBuilder(
        selectedThread: ChatThread? = nil,
        selectedProject: ProjectRef? = nil,
        selectedSidebarThreads: [ChatThread] = [],
        sidebarSelectionIsActive: Bool = false,
        sidebarItemCount: Int = 0,
        sidebarSavedSearches: [SidebarSavedSearch] = [],
        hasActiveWorkspaceRoot: Bool = false,
        canRetryLastUserTurn: Bool = false,
        composerIsSending: Bool = false,
        terminalHasEntries: Bool = false,
        terminalIsRunning: Bool = false,
        browserCanGoBack: Bool = false,
        browserCanGoForward: Bool = false,
        browserCanReload: Bool = false,
        browserCanOpenSession: Bool = false,
        canNavigateBack: Bool = false,
        canNavigateForward: Bool = false,
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        mcpServerProbeSummaries: [String: MCPServerProbeSummary] = [:],
        computerUseStatus: ComputerUseStatus = .permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        ),
        selectedThreadIsRunning: Bool = false,
        runningThreadIDs: Set<UUID> = []
    ) -> WorkspaceCommandSurfaceBuilder {
        WorkspaceCommandSurfaceBuilder(
            selectedThread: selectedThread,
            selectedProject: selectedProject,
            selectedSidebarThreads: selectedSidebarThreads,
            sidebarSelectionIsActive: sidebarSelectionIsActive,
            sidebarItemCount: sidebarItemCount,
            sidebarSavedSearches: sidebarSavedSearches,
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot,
            canRetryLastUserTurn: canRetryLastUserTurn,
            composerIsSending: composerIsSending,
            terminalHasEntries: terminalHasEntries,
            terminalIsRunning: terminalIsRunning,
            browserCanGoBack: browserCanGoBack,
            browserCanGoForward: browserCanGoForward,
            browserCanReload: browserCanReload,
            browserCanOpenSession: browserCanOpenSession,
            canNavigateBack: canNavigateBack,
            canNavigateForward: canNavigateForward,
            mcpServerStatuses: mcpServerStatuses,
            mcpServerProbeSummaries: mcpServerProbeSummaries,
            computerUseStatus: computerUseStatus,
            selectedThreadIsRunning: selectedThreadIsRunning,
            runningThreadIDs: runningThreadIDs
        )
    }

    private func command(
        _ id: String,
        in commands: [WorkspaceCommandSurface],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WorkspaceCommandSurface {
        try XCTUnwrap(commands.first { $0.id == id }, "Missing command \(id)", file: file, line: line)
    }

    private func index(
        of id: String,
        in commandIDs: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int {
        guard let index = commandIDs.firstIndex(of: id) else {
            XCTFail("Missing command \(id)", file: file, line: line)
            return Int.max
        }
        return index
    }
}
