import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceCommandActionPlannerTests: XCTestCase {
    func testContextFreeActionsMapToEffects() {
        let planner = WorkspaceCommandActionPlanner()

        XCTAssertEqual(planner.effect(for: .newChat), .newChat)
        XCTAssertEqual(planner.effect(for: .toggleTerminal), .toggleTerminal)
        XCTAssertEqual(planner.effect(for: .clearTerminal), .clearTerminal)
        XCTAssertEqual(planner.effect(for: .toggleBrowser), .toggleBrowser)
        XCTAssertEqual(planner.effect(for: .browserBack), .browserBack)
        XCTAssertEqual(planner.effect(for: .browserForward), .browserForward)
        XCTAssertEqual(planner.effect(for: .browserReload), .browserReload)
        XCTAssertEqual(planner.effect(for: .toggleExtensions), .toggleExtensions)
        XCTAssertEqual(planner.effect(for: .toggleMemories), .toggleMemories)
        XCTAssertEqual(planner.effect(for: .toggleActivity), .toggleActivity)
        XCTAssertEqual(planner.effect(for: .toggleAutomations), .toggleAutomations)
        XCTAssertEqual(planner.effect(for: .createThreadFollowUp), .createThreadFollowUp)
        XCTAssertEqual(planner.effect(for: .createWorkspaceSchedule), .createWorkspaceSchedule)
        XCTAssertEqual(planner.effect(for: .createThreadFollowUpTomorrow), .createThreadFollowUpTomorrow)
        XCTAssertEqual(planner.effect(for: .createWorkspaceScheduleTomorrow), .createWorkspaceScheduleTomorrow)
        XCTAssertEqual(planner.effect(for: .retryLastTurn), .retryLastTurn)
        XCTAssertEqual(planner.effect(for: .forkFromLast), .forkThread(.latestTurn))
        XCTAssertEqual(planner.effect(for: .forkWithSummary), .forkThread(.summarizedContext))
        XCTAssertEqual(planner.effect(for: .forkFullContext), .forkThread(.fullContext))
        XCTAssertEqual(planner.effect(for: .compactContext), .compactContext)
        XCTAssertEqual(planner.effect(for: .disconnectAll), .disconnectAll)
    }

    func testProjectActionsRequireOnlyTheContextTheyUse() {
        let project = ProjectRef(name: "QuillCode", path: "/repo")
        let planner = WorkspaceCommandActionPlanner(
            selectedProjectID: project.id,
            selectedProject: project
        )

        XCTAssertEqual(
            planner.effect(for: .projectNewChat),
            .newProjectThread(projectID: project.id)
        )
        XCTAssertEqual(
            planner.effect(for: .projectRefreshContext),
            .refreshProjectContext(projectID: project.id)
        )
        XCTAssertEqual(
            planner.effect(for: .projectRename),
            .setDraft("/project rename QuillCode")
        )
        XCTAssertEqual(
            planner.effect(for: .projectRemove),
            .removeProject(projectID: project.id)
        )

        let staleSelection = WorkspaceCommandActionPlanner(selectedProjectID: project.id)
        XCTAssertEqual(staleSelection.effect(for: .projectRemove), .removeProject(projectID: project.id))
        XCTAssertNil(staleSelection.effect(for: .projectRename))
        XCTAssertNil(WorkspaceCommandActionPlanner().effect(for: .projectNewChat))
    }

    func testThreadActionsUseSelectedThreadIDAndTitleAppropriately() {
        let thread = ChatThread(title: "Fix CI")
        let planner = WorkspaceCommandActionPlanner(
            selectedThreadID: thread.id,
            selectedThread: thread
        )

        XCTAssertEqual(planner.effect(for: .threadRename), .setDraft("/rename Fix CI"))
        XCTAssertEqual(planner.effect(for: .threadDuplicate), .duplicateThread(threadID: thread.id))
        XCTAssertEqual(planner.effect(for: .threadArchive), .archiveThread(threadID: thread.id))
        XCTAssertEqual(planner.effect(for: .threadUnarchive), .unarchiveThread(threadID: thread.id))
        XCTAssertEqual(planner.effect(for: .threadDelete), .deleteThread(threadID: thread.id))

        let staleSelection = WorkspaceCommandActionPlanner(selectedThreadID: thread.id)
        XCTAssertEqual(staleSelection.effect(for: .threadArchive), .archiveThread(threadID: thread.id))
        XCTAssertNil(staleSelection.effect(for: .threadRename))
        XCTAssertNil(WorkspaceCommandActionPlanner().effect(for: .threadDuplicate))
    }

    func testSidebarBulkActionsMapToBulkEffects() {
        let planner = WorkspaceCommandActionPlanner()
        let expectations: [(WorkspaceCommandAction, SidebarBulkActionKind)] = [
            (.threadSelectionStart, .select),
            (.threadSelectionSelectAll, .selectAll),
            (.threadSelectionClear, .clearSelection),
            (.threadBulkPin, .pin),
            (.threadBulkUnpin, .unpin),
            (.threadBulkArchive, .archive),
            (.threadBulkUnarchive, .unarchive),
            (.threadBulkDelete, .delete)
        ]

        for (action, kind) in expectations {
            XCTAssertEqual(planner.effect(for: action), .sidebarBulkAction(kind))
        }
    }
}
