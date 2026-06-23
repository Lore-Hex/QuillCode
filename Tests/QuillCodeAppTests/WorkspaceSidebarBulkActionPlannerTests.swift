import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSidebarBulkActionPlannerTests: XCTestCase {
    func testSelectActionsProduceSelectionOnlyPlans() throws {
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        let threads = [first, second]
        let empty = SidebarSelectionState()

        let start = try XCTUnwrap(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .select,
            selection: empty,
            orderedSidebarThreadIDs: threads.map(\.id),
            threads: threads,
            selectedThreadID: first.id
        ))
        XCTAssertTrue(start.nextSelection.isActive)
        XCTAssertTrue(start.nextSelection.selectedThreadIDs.isEmpty)
        XCTAssertNil(start.mutation)

        let selectAll = try XCTUnwrap(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .selectAll,
            selection: empty,
            orderedSidebarThreadIDs: [second.id, first.id],
            threads: threads,
            selectedThreadID: first.id
        ))
        XCTAssertEqual(selectAll.nextSelection.selectedThreadIDs, [second.id, first.id])
        XCTAssertNil(selectAll.mutation)

        let clear = try XCTUnwrap(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .clearSelection,
            selection: selectAll.nextSelection,
            orderedSidebarThreadIDs: threads.map(\.id),
            threads: threads,
            selectedThreadID: first.id
        ))
        XCTAssertFalse(clear.nextSelection.isActive)
        XCTAssertTrue(clear.nextSelection.selectedThreadIDs.isEmpty)
        XCTAssertNil(clear.mutation)
    }

    func testPinAndUnpinUseVisibleResolvedSelectionOrder() throws {
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        let staleID = UUID()
        let selection = SidebarSelectionState(
            isActive: true,
            selectedThreadIDs: [staleID, first.id, second.id]
        )

        let pin = try XCTUnwrap(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .pin,
            selection: selection,
            orderedSidebarThreadIDs: [second.id, first.id],
            threads: [first, second],
            selectedThreadID: first.id
        ))
        XCTAssertEqual(pin.mutation, .pin([second.id, first.id]))
        XCTAssertEqual(pin.followUpSelection, .unchanged)
        XCTAssertFalse(pin.nextSelection.isActive)

        let unpin = try XCTUnwrap(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .unpin,
            selection: selection,
            orderedSidebarThreadIDs: [second.id, first.id],
            threads: [first, second],
            selectedThreadID: first.id
        ))
        XCTAssertEqual(unpin.mutation, .unpin([second.id, first.id]))
    }

    func testMutationsReturnNilWhenSelectionIsEmptyAfterPruning() {
        let thread = ChatThread(title: "Thread")
        let selection = SidebarSelectionState(
            isActive: true,
            selectedThreadIDs: [UUID()]
        )

        XCTAssertNil(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .archive,
            selection: selection,
            orderedSidebarThreadIDs: [thread.id],
            threads: [thread],
            selectedThreadID: thread.id
        ))
    }

    func testArchiveSelectedThreadRequestsBestFallbackSelection() throws {
        let projectID = UUID()
        let selected = ChatThread(title: "Selected", projectID: projectID)
        let other = ChatThread(title: "Other", projectID: projectID)
        let selection = SidebarSelectionState(
            isActive: true,
            selectedThreadIDs: [selected.id, other.id]
        )

        let plan = try XCTUnwrap(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .archive,
            selection: selection,
            orderedSidebarThreadIDs: [selected.id, other.id],
            threads: [selected, other],
            selectedThreadID: selected.id
        ))

        XCTAssertEqual(plan.mutation, .archive([selected.id, other.id]))
        XCTAssertEqual(plan.followUpSelection, .selectBestAfterRemoving(preferredProjectID: projectID))
    }

    func testUnarchiveSelectsFirstVisibleTarget() throws {
        let projectID = UUID()
        let first = ChatThread(title: "First", projectID: projectID)
        let second = ChatThread(title: "Second")
        let selection = SidebarSelectionState(
            isActive: true,
            selectedThreadIDs: [first.id, second.id]
        )

        let plan = try XCTUnwrap(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .unarchive,
            selection: selection,
            orderedSidebarThreadIDs: [second.id, first.id],
            threads: [first, second],
            selectedThreadID: nil
        ))

        XCTAssertEqual(plan.mutation, .unarchive([second.id, first.id]))
        XCTAssertEqual(
            plan.followUpSelection,
            .select(WorkspaceSidebarBulkActionPlanner.ThreadContext(second))
        )
    }

    func testDeleteReconcilesWhenCurrentThreadIsNotDeleted() throws {
        let selected = ChatThread(title: "Selected")
        let deleted = ChatThread(title: "Deleted")
        let selection = SidebarSelectionState(
            isActive: true,
            selectedThreadIDs: [deleted.id]
        )

        let plan = try XCTUnwrap(WorkspaceSidebarBulkActionPlanner.plan(
            kind: .delete,
            selection: selection,
            orderedSidebarThreadIDs: [deleted.id],
            threads: [selected, deleted],
            selectedThreadID: selected.id
        ))

        XCTAssertEqual(plan.mutation, .delete([deleted.id]))
        XCTAssertEqual(plan.followUpSelection, .reconcileCurrent)
    }
}
