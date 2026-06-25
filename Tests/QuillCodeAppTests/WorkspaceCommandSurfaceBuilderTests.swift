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
        XCTAssertEqual(try command("find-in-chat", in: commands).isEnabled, false)
        XCTAssertEqual(try command("project-new-chat", in: commands).isEnabled, false)
        XCTAssertEqual(try command("git-status", in: commands).isEnabled, false)
        XCTAssertEqual(try command("terminal-clear", in: commands).isEnabled, false)
        XCTAssertEqual(try command("open-browser-session", in: commands).isEnabled, false)
        XCTAssertEqual(try command("stop-all", in: commands).isEnabled, false)
        XCTAssertEqual(try command("disconnect-all", in: commands).isEnabled, false)
        XCTAssertEqual(try command("computer-use-setup", in: commands).isEnabled, true)
        XCTAssertEqual(try command("computer-use-open-screen-recording", in: commands).isEnabled, true)
        XCTAssertEqual(try command("computer-use-open-accessibility", in: commands).isEnabled, true)
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

        XCTAssertLessThan(index(of: "retry-last-turn", in: commandIDs), index(of: "search", in: commandIDs))
        XCTAssertLessThan(index(of: "toggle-extensions", in: commandIDs), index(of: "git-status", in: commandIDs))
        XCTAssertLessThan(index(of: "git-worktree-remove", in: commandIDs), index(of: "git-worktree-prune", in: commandIDs))
        XCTAssertLessThan(index(of: "git-worktree-prune", in: commandIDs), index(of: "local-env:.quillcode/actions/bootstrap.sh", in: commandIDs))
        XCTAssertLessThan(index(of: "local-env:.quillcode/actions/bootstrap.sh", in: commandIDs), index(of: "mcp-start:mcp_server:filesystem", in: commandIDs))
        XCTAssertLessThan(index(of: "mcp-stop:mcp_server:filesystem", in: commandIDs), index(of: "extension-update:mcp_server:filesystem", in: commandIDs))
        XCTAssertLessThan(index(of: "extension-update:mcp_server:filesystem", in: commandIDs), index(of: "stop-all", in: commandIDs))
    }

    func testSelectedThreadAndSidebarSelectionEnableThreadCommands() throws {
        let selectedThread = ChatThread(messages: [.init(role: .user, content: "Run whoami")])
        let pinnedThread = ChatThread(title: "Pinned", isPinned: true)
        let archivedThread = ChatThread(title: "Archived", isArchived: true)
        let commands = makeBuilder(
            selectedThread: selectedThread,
            selectedSidebarThreads: [pinnedThread, archivedThread],
            sidebarSelectionIsActive: true,
            sidebarItemCount: 3,
            canRetryLastUserTurn: true
        ).commands

        XCTAssertEqual(try command("thread-rename", in: commands).isEnabled, true)
        XCTAssertEqual(try command("fork-from-last", in: commands).isEnabled, true)
        XCTAssertEqual(try command("compact-context", in: commands).isEnabled, true)
        XCTAssertEqual(try command("find-in-chat", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-selection-clear", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-pin", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-unpin", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-archive", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-unarchive", in: commands).isEnabled, true)
        XCTAssertEqual(try command("thread-bulk-delete", in: commands).isEnabled, true)
        XCTAssertEqual(try command("retry-last-turn", in: commands).isEnabled, true)
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
            version: "1.2.0",
            sourceURL: "https://github.com/Lore-Hex/quillcode-github",
            relativePath: ".quillcode/plugins/github.json",
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
            mcpServerStatuses: ["mcp_server:filesystem": .ready]
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
        XCTAssertEqual(try command("toggle-extensions", in: commands).isEnabled, true)
        XCTAssertEqual(try command("git-status", in: commands).isEnabled, true)
        XCTAssertEqual(try command("extension-update:plugin:github", in: commands).isEnabled, true)
        XCTAssertEqual(try command("mcp-start:mcp_server:filesystem", in: commands).isEnabled, false)
        XCTAssertEqual(try command("mcp-stop:mcp_server:filesystem", in: commands).isEnabled, true)
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
        hasActiveWorkspaceRoot: Bool = false,
        canRetryLastUserTurn: Bool = false,
        composerIsSending: Bool = false,
        terminalHasEntries: Bool = false,
        terminalIsRunning: Bool = false,
        browserCanGoBack: Bool = false,
        browserCanGoForward: Bool = false,
        browserCanReload: Bool = false,
        browserCanOpenSession: Bool = false,
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        computerUseStatus: ComputerUseStatus = .permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        )
    ) -> WorkspaceCommandSurfaceBuilder {
        WorkspaceCommandSurfaceBuilder(
            selectedThread: selectedThread,
            selectedProject: selectedProject,
            selectedSidebarThreads: selectedSidebarThreads,
            sidebarSelectionIsActive: sidebarSelectionIsActive,
            sidebarItemCount: sidebarItemCount,
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot,
            canRetryLastUserTurn: canRetryLastUserTurn,
            composerIsSending: composerIsSending,
            terminalHasEntries: terminalHasEntries,
            terminalIsRunning: terminalIsRunning,
            browserCanGoBack: browserCanGoBack,
            browserCanGoForward: browserCanGoForward,
            browserCanReload: browserCanReload,
            browserCanOpenSession: browserCanOpenSession,
            mcpServerStatuses: mcpServerStatuses,
            computerUseStatus: computerUseStatus
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
