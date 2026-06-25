import XCTest
import QuillCodeCore
import QuillComputerUseKit
@testable import QuillCodeApp

final class QuillCodeWorkspaceViewCommandPlannerTests: XCTestCase {
    func testViewLocalCommandsMapToPresentationActions() {
        let planner = makePlanner()

        XCTAssertEqual(planner.action(for: command("settings")), .presentSettings)
        XCTAssertEqual(planner.action(for: command("computer-use-setup")), .presentSettings)
        XCTAssertEqual(planner.action(for: command("search")), .presentSearch)
        XCTAssertEqual(planner.action(for: command("find-in-chat")), .presentFind)
        XCTAssertEqual(planner.action(for: command("add-project")), .requestAddProject)
        XCTAssertEqual(planner.action(for: command("command-palette")), .presentCommandPalette)
        XCTAssertEqual(planner.action(for: command("keyboard-shortcuts")), .presentKeyboardShortcuts)
        XCTAssertEqual(planner.action(for: command("git-worktree-create")), .presentCreateWorktree)
        XCTAssertEqual(planner.action(for: command("git-worktree-open")), .presentOpenWorktree)
        XCTAssertEqual(planner.action(for: command("git-worktree-remove")), .presentRemoveWorktree)
        XCTAssertEqual(planner.action(for: command("open-browser-session")), .openBrowserSession)
    }

    func testRenameCommandsUseSelectedItems() throws {
        let threadID = UUID()
        let projectID = UUID()
        let planner = makePlanner(
            sidebar: sidebar(threadID: threadID, title: "Investigate CI", selectedThreadID: threadID),
            projects: projects(projectID: projectID, name: "QuillCode", selectedProjectID: projectID)
        )

        XCTAssertEqual(
            planner.action(for: command("thread-rename")),
            .renameThread(threadID: threadID, title: "Investigate CI")
        )
        XCTAssertEqual(
            planner.action(for: command("project-rename")),
            .renameProject(projectID: projectID, name: "QuillCode")
        )
    }

    func testRenameCommandsNoopWhenSelectionIsMissing() {
        let threadID = UUID()
        let projectID = UUID()
        let planner = makePlanner(
            sidebar: sidebar(threadID: threadID, title: "Unselected", selectedThreadID: nil),
            projects: projects(projectID: projectID, name: "Unselected", selectedProjectID: nil)
        )

        XCTAssertNil(planner.action(for: command("thread-rename")))
        XCTAssertNil(planner.action(for: command("project-rename")))
    }

    func testDispatchedCommandsPreserveComposerFocusRules() throws {
        let planner = makePlanner()
        let slashCommand = try XCTUnwrap(SlashCommandCatalog.commandPaletteCommands().first)
        let memoryCommand = command("memory-add")
        let sshCommand = command("add-ssh-project")
        let sessionCommand = command("open-browser-session")
        let genericCommand = command("git-status")

        XCTAssertEqual(
            planner.action(for: slashCommand),
            .dispatch(command: slashCommand, focusesComposer: true)
        )
        XCTAssertEqual(
            planner.action(for: memoryCommand),
            .dispatch(command: memoryCommand, focusesComposer: true)
        )
        XCTAssertEqual(
            planner.action(for: sshCommand),
            .dispatch(command: sshCommand, focusesComposer: true)
        )
        XCTAssertEqual(
            planner.action(for: sessionCommand),
            .openBrowserSession
        )
        XCTAssertEqual(
            planner.action(for: genericCommand),
            .dispatch(command: genericCommand, focusesComposer: false)
        )
    }

    func testHostOwnedComputerUseCommandsDispatchThroughHost() {
        let planner = makePlanner()

        XCTAssertEqual(
            planner.action(for: command("computer-use-open-screen-recording")),
            .dispatch(command: command("computer-use-open-screen-recording"), focusesComposer: false)
        )
        XCTAssertEqual(
            planner.action(for: command("computer-use-open-accessibility")),
            .dispatch(command: command("computer-use-open-accessibility"), focusesComposer: false)
        )
        XCTAssertEqual(
            planner.action(for: command("computer-use-refresh")),
            .dispatch(command: command("computer-use-refresh"), focusesComposer: false)
        )
    }

    func testUnknownCommandsDoNotDispatchAsSilentNoops() {
        let planner = makePlanner()

        XCTAssertNil(planner.action(for: command("unknown-command")))
    }

    func testCommandSurfaceEmitsOnlyPresentableOrDispatchableCommands() throws {
        let threadID = UUID()
        let projectID = UUID()
        let selectedThread = ChatThread(
            id: threadID,
            title: "Investigate CI",
            messages: [.init(role: .user, content: "Run tests")]
        )
        let selectedProject = ProjectRef(
            id: projectID,
            name: "QuillCode",
            path: "/repo",
            localActions: [
                LocalEnvironmentAction(
                    id: "local-env:.quillcode/actions/bootstrap.sh",
                    title: "Bootstrap",
                    relativePath: ".quillcode/actions/bootstrap.sh",
                    command: "sh .quillcode/actions/bootstrap.sh"
                )
            ],
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    launchExecutable: "quill-mcp",
                    updateCommand: "quill-mcp update"
                )
            ]
        )
        let commands = WorkspaceCommandSurfaceBuilder(
            selectedThread: selectedThread,
            selectedProject: selectedProject,
            selectedSidebarThreads: [
                ChatThread(title: "Pinned", isPinned: true),
                ChatThread(title: "Archived", isArchived: true)
            ],
            sidebarSelectionIsActive: true,
            sidebarItemCount: 3,
            hasActiveWorkspaceRoot: true,
            canRetryLastUserTurn: true,
            composerIsSending: true,
            terminalHasEntries: true,
            terminalIsRunning: false,
            browserCanGoBack: true,
            browserCanGoForward: true,
            browserCanReload: true,
            browserCanOpenSession: true,
            mcpServerStatuses: ["mcp_server:filesystem": .ready],
            computerUseStatus: .permissionStatus(
                screenRecordingGranted: false,
                accessibilityGranted: false
            )
        ).commands
        let planner = makePlanner(
            sidebar: SidebarSurface(
                items: [SidebarItemSurface(item: SidebarItem(thread: selectedThread), selectedThreadID: threadID)],
                selectedThreadID: threadID
            ),
            projects: ProjectListSurface(
                items: [ProjectItemSurface(project: selectedProject, selectedProjectID: projectID)],
                selectedProjectID: projectID
            )
        )

        let missingCommands = commands.filter { planner.action(for: $0) == nil }.map(\.id)

        XCTAssertEqual(missingCommands, [])
    }

    private func makePlanner(
        sidebar: SidebarSurface = SidebarSurface(items: [], selectedThreadID: nil),
        projects: ProjectListSurface = ProjectListSurface(items: [], selectedProjectID: nil)
    ) -> WorkspaceViewCommandPlanner {
        WorkspaceViewCommandPlanner(sidebar: sidebar, projects: projects)
    }

    private func command(_ id: String) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(id: id, title: id)
    }

    private func sidebar(
        threadID: UUID,
        title: String,
        selectedThreadID: UUID?
    ) -> SidebarSurface {
        let thread = ChatThread(id: threadID, title: title)
        return SidebarSurface(
            items: [SidebarItemSurface(item: SidebarItem(thread: thread), selectedThreadID: selectedThreadID)],
            selectedThreadID: selectedThreadID
        )
    }

    private func projects(
        projectID: UUID,
        name: String,
        selectedProjectID: UUID?
    ) -> ProjectListSurface {
        let project = ProjectRef(id: projectID, name: name, path: "/repo")
        return ProjectListSurface(
            items: [ProjectItemSurface(project: project, selectedProjectID: selectedProjectID)],
            selectedProjectID: selectedProjectID
        )
    }
}
