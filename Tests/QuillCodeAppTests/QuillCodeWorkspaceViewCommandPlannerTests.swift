import XCTest
import QuillCodeCore
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
        XCTAssertEqual(planner.action(for: command("git-worktree-remove")), .presentRemoveWorktree)
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
            planner.action(for: genericCommand),
            .dispatch(command: genericCommand, focusesComposer: false)
        )
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
