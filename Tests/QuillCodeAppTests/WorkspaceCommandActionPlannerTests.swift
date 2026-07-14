import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceCommandActionPlannerTests: XCTestCase {
    func testContextFreeActionsMapToEffects() {
        let planner = WorkspaceCommandActionPlanner()

        XCTAssertEqual(planner.effect(for: .newChat), .newChat)
        XCTAssertEqual(planner.effect(for: .quickChat), .quickChat)
        XCTAssertEqual(planner.effect(for: .workspaceBack), .workspaceBack)
        XCTAssertEqual(planner.effect(for: .workspaceForward), .workspaceForward)
        XCTAssertEqual(planner.effect(for: .previousTask), .selectAdjacentTask(offset: -1))
        XCTAssertEqual(planner.effect(for: .nextTask), .selectAdjacentTask(offset: 1))
        XCTAssertEqual(planner.effect(for: .toggleSidebar), .toggleSidebar)
        XCTAssertEqual(planner.effect(for: .toggleTerminal), .toggleTerminal)
        XCTAssertEqual(planner.effect(for: .toggleBottomPanel), .toggleTerminal)
        XCTAssertEqual(planner.effect(for: .toggleReviewPanel), .toggleReviewPanel)
        XCTAssertEqual(planner.effect(for: .increaseFontSize), .increaseTextScale)
        XCTAssertEqual(planner.effect(for: .decreaseFontSize), .decreaseTextScale)
        XCTAssertEqual(planner.effect(for: .clearTerminal), .clearTerminal)
        XCTAssertEqual(planner.effect(for: .toggleBrowser), .toggleBrowser)
        XCTAssertEqual(planner.effect(for: .browserBack), .browserBack)
        XCTAssertEqual(planner.effect(for: .browserForward), .browserForward)
        XCTAssertEqual(planner.effect(for: .browserReload), .browserReload)
        XCTAssertEqual(planner.effect(for: .toggleExtensions), .toggleExtensions)
        XCTAssertEqual(planner.effect(for: .toggleMemories), .toggleMemories)
        XCTAssertEqual(planner.effect(for: .toggleActivity), .toggleActivity)
        XCTAssertEqual(planner.effect(for: .toggleAutomations), .toggleAutomations)
        XCTAssertEqual(planner.effect(for: .pullRequestReviewDraft), .openPullRequestReviewDraft)
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
        // New-worktree is context-free: the model resolves the selected project when it runs.
        XCTAssertEqual(planner.effect(for: .threadNewWorktree), .newWorktreeThread)
        XCTAssertEqual(planner.effect(for: .threadHandoff), .handoffSelectedThread)
        XCTAssertEqual(planner.effect(for: .threadFinishWorktree), .finishSelectedWorktree)
        XCTAssertEqual(planner.effect(for: .threadPublishBranch), .publishSelectedWorktreeBranch)
        XCTAssertEqual(planner.effect(for: .threadRefreshPullRequest), .refreshSelectedPullRequest)
        XCTAssertEqual(planner.effect(for: .threadLandPullRequest), .landSelectedPullRequest)
        XCTAssertEqual(planner.effect(for: .threadCleanupMergedWorktree), .cleanUpSelectedMergedWorktree)
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
            planner.effect(for: .projectMoveToTop),
            .moveProjectToTop(projectID: project.id)
        )
        XCTAssertEqual(
            planner.effect(for: .projectMoveUp),
            .moveProject(projectID: project.id, direction: .up)
        )
        XCTAssertEqual(
            planner.effect(for: .projectMoveDown),
            .moveProject(projectID: project.id, direction: .down)
        )
        XCTAssertEqual(
            planner.effect(for: .projectMoveToBottom),
            .moveProjectToBottom(projectID: project.id)
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
        XCTAssertEqual(staleSelection.effect(for: .projectMoveUp), .moveProject(projectID: project.id, direction: .up))
        XCTAssertEqual(staleSelection.effect(for: .projectMoveToBottom), .moveProjectToBottom(projectID: project.id))
        XCTAssertNil(staleSelection.effect(for: .projectRename))
        XCTAssertNil(WorkspaceCommandActionPlanner().effect(for: .projectNewChat))
        XCTAssertNil(WorkspaceCommandActionPlanner().effect(for: .projectMoveToTop))
        XCTAssertNil(WorkspaceCommandActionPlanner().effect(for: .projectMoveToBottom))
    }

    func testThreadActionsUseSelectedThreadIDAndTitleAppropriately() {
        let thread = ChatThread(title: "Fix CI")
        var pinnedThread = ChatThread(title: "Pinned")
        pinnedThread.isPinned = true
        var archivedThread = ChatThread(title: "Archived")
        archivedThread.isArchived = true
        let planner = WorkspaceCommandActionPlanner(
            selectedThreadID: thread.id,
            selectedThread: thread
        )

        XCTAssertEqual(planner.effect(for: .threadRename), .setDraft("/rename Fix CI"))
        XCTAssertEqual(planner.effect(for: .threadDuplicate), .duplicateThread(threadID: thread.id))
        XCTAssertEqual(planner.effect(for: .threadPin), .setThreadPinned(threadID: thread.id, isPinned: true))
        XCTAssertNil(planner.effect(for: .threadUnpin))
        XCTAssertEqual(planner.effect(for: .threadClear), .clearThread(threadID: thread.id))
        XCTAssertEqual(planner.effect(for: .threadArchive), .archiveThread(threadID: thread.id))
        XCTAssertEqual(planner.effect(for: .threadUnarchive), .unarchiveThread(threadID: thread.id))
        XCTAssertEqual(planner.effect(for: .threadDelete), .deleteThread(threadID: thread.id))
        XCTAssertEqual(
            WorkspaceCommandActionPlanner(
                selectedThreadID: pinnedThread.id,
                selectedThread: pinnedThread
            ).effect(for: .threadUnpin),
            .setThreadPinned(threadID: pinnedThread.id, isPinned: false)
        )
        XCTAssertNil(WorkspaceCommandActionPlanner(
            selectedThreadID: pinnedThread.id,
            selectedThread: pinnedThread
        ).effect(for: .threadPin))
        XCTAssertNil(WorkspaceCommandActionPlanner(
            selectedThreadID: archivedThread.id,
            selectedThread: archivedThread
        ).effect(for: .threadPin))

        let staleSelection = WorkspaceCommandActionPlanner(selectedThreadID: thread.id)
        XCTAssertEqual(staleSelection.effect(for: .threadClear), .clearThread(threadID: thread.id))
        XCTAssertEqual(staleSelection.effect(for: .threadArchive), .archiveThread(threadID: thread.id))
        XCTAssertNil(staleSelection.effect(for: .threadPin))
        XCTAssertNil(staleSelection.effect(for: .threadUnpin))
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

    func testRestoreWorktreeRequiresSelectedRestorableSnapshot() {
        var thread = ChatThread(title: "Archived task")
        thread.worktree = WorktreeBinding(
            path: "/tmp/quillcode-missing-\(UUID().uuidString)",
            branch: "",
            snapshot: WorktreeSnapshotReference(
                headCommit: String(repeating: "a", count: 40),
                fileCount: 1,
                byteCount: 12
            )
        )
        let planner = WorkspaceCommandActionPlanner(
            selectedThreadID: thread.id,
            selectedThread: thread
        )

        XCTAssertEqual(
            planner.effect(for: .threadRestoreWorktree),
            .restoreManagedWorktree(threadID: thread.id)
        )
        XCTAssertNil(WorkspaceCommandActionPlanner(
            selectedThreadID: thread.id,
            selectedThread: ChatThread(title: "No snapshot")
        ).effect(for: .threadRestoreWorktree))
    }
}
