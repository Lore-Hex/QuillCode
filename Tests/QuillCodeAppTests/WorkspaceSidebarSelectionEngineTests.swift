import XCTest
@testable import QuillCodeApp

final class WorkspaceSidebarSelectionEngineTests: XCTestCase {
    func testStartActivatesAndOptionallySelectsValidThread() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let stale = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!

        let selected = WorkspaceSidebarSelectionEngine.start(
            selecting: first,
            state: SidebarSelectionState(),
            validThreadIDs: [first]
        )
        let ignored = WorkspaceSidebarSelectionEngine.start(
            selecting: stale,
            state: SidebarSelectionState(),
            validThreadIDs: [first]
        )

        XCTAssertTrue(selected.isActive)
        XCTAssertEqual(selected.selectedThreadIDs, [first])
        XCTAssertTrue(ignored.isActive)
        XCTAssertTrue(ignored.selectedThreadIDs.isEmpty)
    }

    func testSelectAllActivatesOnlyWhenThereAreSidebarItems() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let selected = WorkspaceSidebarSelectionEngine.selectAll(orderedThreadIDs: [first, second])
        let empty = WorkspaceSidebarSelectionEngine.selectAll(orderedThreadIDs: [])

        XCTAssertTrue(selected.isActive)
        XCTAssertEqual(selected.selectedThreadIDs, [first, second])
        XCTAssertFalse(empty.isActive)
        XCTAssertTrue(empty.selectedThreadIDs.isEmpty)
    }

    func testToggleActivatesFlipsSelectionAndRejectsUnknownThreads() throws {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let stale = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let initial = SidebarSelectionState()

        let selected = try XCTUnwrap(WorkspaceSidebarSelectionEngine.toggle(
            first,
            state: initial,
            validThreadIDs: [first]
        ))
        let deselected = try XCTUnwrap(WorkspaceSidebarSelectionEngine.toggle(
            first,
            state: selected,
            validThreadIDs: [first]
        ))

        XCTAssertTrue(selected.isActive)
        XCTAssertEqual(selected.selectedThreadIDs, [first])
        XCTAssertTrue(deselected.isActive)
        XCTAssertTrue(deselected.selectedThreadIDs.isEmpty)
        XCTAssertNil(WorkspaceSidebarSelectionEngine.toggle(
            stale,
            state: selected,
            validThreadIDs: [first]
        ))
    }

    func testResolvePrunesStaleIDsAndReturnsSidebarOrder() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let stale = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let state = SidebarSelectionState(
            isActive: true,
            selectedThreadIDs: [second, first, stale]
        )

        let resolution = WorkspaceSidebarSelectionEngine.resolve(
            state: state,
            orderedSidebarThreadIDs: [third, first, second],
            validThreadIDs: [first, second, third]
        )

        XCTAssertTrue(resolution.state.isActive)
        XCTAssertEqual(resolution.state.selectedThreadIDs, [first, second])
        XCTAssertEqual(resolution.selectedThreadIDs, [first, second])
    }

    func testResolveKeepsActiveEmptySelectionWhenAllSelectedIDsAreStale() {
        let stale = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let state = SidebarSelectionState(isActive: true, selectedThreadIDs: [stale])

        let resolution = WorkspaceSidebarSelectionEngine.resolve(
            state: state,
            orderedSidebarThreadIDs: [],
            validThreadIDs: []
        )

        XCTAssertTrue(resolution.state.isActive)
        XCTAssertTrue(resolution.state.selectedThreadIDs.isEmpty)
        XCTAssertTrue(resolution.selectedThreadIDs.isEmpty)
    }
}
