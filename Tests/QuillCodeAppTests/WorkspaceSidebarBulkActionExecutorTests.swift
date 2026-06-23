import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSidebarBulkActionExecutorTests: XCTestCase {
    func testSelectionOnlyPlanUpdatesSelectionWithoutPersistingWorkspace() throws {
        let thread = ChatThread(title: "Thread")
        let selection = SidebarSelectionState(isActive: true, selectedThreadIDs: [thread.id])
        let plan = WorkspaceSidebarBulkActionPlanner.Plan.selectionOnly(selection)

        let result = try XCTUnwrap(execute(plan, threads: [thread]))

        XCTAssertEqual(result.nextSelection, selection)
        XCTAssertEqual(result.threads, [thread])
        XCTAssertTrue(result.changedThreads.isEmpty)
        XCTAssertTrue(result.removedThreads.isEmpty)
        XCTAssertFalse(result.shouldSaveProjects)
        XCTAssertFalse(result.shouldSyncTerminalSession)
        XCTAssertNil(result.projectIDToTouch)
    }

    func testPinAndUnpinReturnChangedThreadsForPersistence() throws {
        let now = Date(timeIntervalSince1970: 100)
        let first = ChatThread(title: "First", isPinned: false, updatedAt: .distantPast)
        let archived = ChatThread(title: "Archived", isPinned: false, isArchived: true, updatedAt: .distantPast)

        let pin = try XCTUnwrap(execute(
            .mutation(.pin([first.id, archived.id])),
            threads: [first, archived],
            now: now
        ))

        XCTAssertEqual(pin.changedThreads.map(\.id), [first.id])
        XCTAssertTrue(try XCTUnwrap(pin.threads.first { $0.id == first.id }).isPinned)
        XCTAssertEqual(try XCTUnwrap(pin.threads.first { $0.id == first.id }).updatedAt, now)
        XCTAssertFalse(try XCTUnwrap(pin.threads.first { $0.id == archived.id }).isPinned)
        XCTAssertTrue(pin.shouldSaveProjects)

        let unpin = try XCTUnwrap(execute(
            .mutation(.unpin([first.id])),
            threads: pin.threads,
            now: now.addingTimeInterval(1)
        ))

        XCTAssertEqual(unpin.changedThreads.map(\.id), [first.id])
        XCTAssertFalse(try XCTUnwrap(unpin.threads.first { $0.id == first.id }).isPinned)
    }

    func testArchiveSelectedThreadUsesBestFallbackSelection() throws {
        let project = project()
        let selected = ChatThread(title: "Selected", projectID: project.id, updatedAt: Date(timeIntervalSince1970: 10))
        let fallback = ChatThread(title: "Fallback", projectID: project.id, updatedAt: Date(timeIntervalSince1970: 20))
        let plan = WorkspaceSidebarBulkActionPlanner.Plan.mutation(
            .archive([selected.id]),
            followUpSelection: .selectBestAfterRemoving(preferredProjectID: project.id)
        )

        let result = try XCTUnwrap(execute(
            plan,
            threads: [selected, fallback],
            projects: [project],
            selectedThreadID: selected.id,
            selectedProjectID: project.id
        ))

        XCTAssertEqual(result.selectedThreadID, fallback.id)
        XCTAssertEqual(result.selectedProjectID, project.id)
        XCTAssertEqual(result.changedThreads.map(\.id), [selected.id])
        XCTAssertTrue(try XCTUnwrap(result.threads.first { $0.id == selected.id }).isArchived)
        XCTAssertTrue(result.shouldSaveProjects)
        XCTAssertTrue(result.shouldSyncTerminalSession)
        XCTAssertNil(result.projectIDToTouch)
    }

    func testUnarchiveSelectsFirstTargetAndRequestsProjectTouch() throws {
        let project = project()
        let archived = ChatThread(title: "Archived", projectID: project.id, isArchived: true)
        let plan = WorkspaceSidebarBulkActionPlanner.Plan.mutation(
            .unarchive([archived.id]),
            followUpSelection: .select(WorkspaceSidebarBulkActionPlanner.ThreadContext(archived))
        )

        let result = try XCTUnwrap(execute(
            plan,
            threads: [archived],
            projects: [project]
        ))

        XCTAssertEqual(result.selectedThreadID, archived.id)
        XCTAssertEqual(result.selectedProjectID, project.id)
        XCTAssertEqual(result.projectIDToTouch, project.id)
        XCTAssertTrue(result.shouldSyncTerminalSession)
        XCTAssertFalse(try XCTUnwrap(result.threads.first { $0.id == archived.id }).isArchived)
    }

    func testDeleteReconcilesSelectedProjectWhenCurrentThreadSurvives() throws {
        let project = project()
        let selected = ChatThread(title: "Selected", projectID: project.id)
        let deleted = ChatThread(title: "Deleted", projectID: project.id)
        let plan = WorkspaceSidebarBulkActionPlanner.Plan.mutation(
            .delete([deleted.id]),
            followUpSelection: .reconcileCurrent
        )

        let result = try XCTUnwrap(execute(
            plan,
            threads: [selected, deleted],
            projects: [project],
            selectedThreadID: selected.id,
            selectedProjectID: nil
        ))

        XCTAssertEqual(result.threads.map(\.id), [selected.id])
        XCTAssertEqual(result.removedThreads.map(\.id), [deleted.id])
        XCTAssertEqual(result.selectedThreadID, selected.id)
        XCTAssertEqual(result.selectedProjectID, project.id)
        XCTAssertFalse(result.shouldSyncTerminalSession)
        XCTAssertTrue(result.shouldSaveProjects)
    }

    private func execute(
        _ plan: WorkspaceSidebarBulkActionPlanner.Plan,
        threads: [ChatThread],
        projects: [ProjectRef] = [],
        selectedThreadID: UUID? = nil,
        selectedProjectID: UUID? = nil,
        now: Date = Date()
    ) -> WorkspaceSidebarBulkActionExecutor.Result? {
        WorkspaceSidebarBulkActionExecutor.execute(
            plan,
            threads: threads,
            projects: projects,
            selectedThreadID: selectedThreadID,
            selectedProjectID: selectedProjectID,
            now: now
        )
    }

    private func project() -> ProjectRef {
        ProjectRef(name: "Project", path: "/repo")
    }
}
