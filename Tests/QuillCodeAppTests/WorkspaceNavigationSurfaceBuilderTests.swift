import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceNavigationSurfaceBuilderTests: XCTestCase {
    func testBuildsSortedProjectsAndSidebarRows() throws {
        let olderProject = ProjectRef(
            name: "Older",
            path: "/tmp/older",
            lastOpenedAt: Date(timeIntervalSince1970: 10)
        )
        let newerProject = ProjectRef(
            name: "Newer",
            path: "/tmp/newer",
            lastOpenedAt: Date(timeIntervalSince1970: 20)
        )
        let selectedThread = ChatThread(title: "Selected")
        let otherThread = ChatThread(title: "Other")

        let surface = WorkspaceNavigationSurfaceBuilder(
            projects: [olderProject, newerProject],
            selectedProjectID: olderProject.id,
            sidebarItems: [SidebarItem(thread: selectedThread), SidebarItem(thread: otherThread)],
            selectedThreadID: selectedThread.id,
            threads: [selectedThread, otherThread],
            activeSidebarFilter: .all,
            selectionIsActive: false,
            selectedThreadIDs: []
        ).surface()

        XCTAssertEqual(surface.projects.items.map(\.name), ["Newer", "Older"])
        XCTAssertEqual(surface.projects.selectedProjectID, olderProject.id)
        XCTAssertEqual(surface.projects.items.map(\.isSelected), [false, true])
        XCTAssertEqual(
            surface.projects.items.map { $0.actions.first(where: { $0.kind == .moveToTop })?.isEnabled },
            [false, true]
        )
        XCTAssertEqual(
            surface.projects.items.map { $0.actions.first(where: { $0.kind == .moveUp })?.isEnabled },
            [false, true]
        )
        XCTAssertEqual(
            surface.projects.items.map { $0.actions.first(where: { $0.kind == .moveDown })?.isEnabled },
            [true, false]
        )
        XCTAssertEqual(
            surface.projects.items.first?.actions.first(where: { $0.kind == .moveToTop })?.disabledReason,
            "Already at the top"
        )
        XCTAssertEqual(
            surface.projects.items.first?.actions.first(where: { $0.kind == .moveUp })?.disabledReason,
            "Already at the top"
        )
        XCTAssertEqual(
            surface.projects.items.last?.actions.first(where: { $0.kind == .moveDown })?.disabledReason,
            "Already at the bottom"
        )
        XCTAssertEqual(surface.sidebar.items.map(\.title), ["Selected", "Other"])
        XCTAssertEqual(surface.sidebar.items.map(\.isSelected), [true, false])
        XCTAssertEqual(surface.sidebar.bulkActions.map(\.kind), [.select])
        XCTAssertEqual(surface.sidebar.bulkActions.first?.isEnabled, true)
    }

    func testInactiveSelectionIgnoresSelectedThreadIDs() throws {
        let thread = ChatThread(title: "Thread")

        let surface = WorkspaceNavigationSurfaceBuilder(
            projects: [],
            selectedProjectID: nil,
            sidebarItems: [SidebarItem(thread: thread)],
            selectedThreadID: thread.id,
            threads: [thread],
            activeSidebarFilter: .all,
            selectionIsActive: false,
            selectedThreadIDs: [thread.id]
        ).surface()

        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectedThreadIDs, [])
        XCTAssertEqual(surface.sidebar.selectionLabel, "No chats selected")
        XCTAssertFalse(try XCTUnwrap(surface.sidebar.items.first).isBulkSelected)
        XCTAssertEqual(surface.sidebar.bulkActions.map(\.kind), [.select])
    }

    func testActiveSelectionBuildsBulkActionAvailability() throws {
        let active = ChatThread(title: "Active")
        var pinned = ChatThread(title: "Pinned")
        pinned.isPinned = true
        var archived = ChatThread(title: "Archived")
        archived.isArchived = true
        let threads = [active, pinned, archived]

        let surface = WorkspaceNavigationSurfaceBuilder(
            projects: [],
            selectedProjectID: nil,
            sidebarItems: threads.map { SidebarItem(thread: $0) },
            selectedThreadID: active.id,
            threads: threads,
            activeSidebarFilter: .all,
            selectionIsActive: true,
            selectedThreadIDs: [active.id, pinned.id, archived.id]
        ).surface()

        XCTAssertTrue(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectedThreadIDs, Set([active.id, pinned.id, archived.id]))
        XCTAssertEqual(surface.sidebar.selectionLabel, "3 chats selected")
        XCTAssertEqual(surface.sidebar.items.map(\.isBulkSelected), [true, true, true])
        XCTAssertEqual(
            surface.sidebar.bulkActions.map(\.kind),
            [.clearSelection, .selectAll, .pin, .unpin, .archive, .unarchive, .delete]
        )
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .selectAll }?.isEnabled, false)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .pin }?.isEnabled, true)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .unpin }?.isEnabled, true)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .archive }?.isEnabled, true)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .unarchive }?.isEnabled, true)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .delete }?.isEnabled, true)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .delete }?.isDestructive, true)
    }

    func testSelectActionDisablesWhenThereAreNoThreads() {
        let surface = WorkspaceNavigationSurfaceBuilder(
            projects: [],
            selectedProjectID: nil,
            sidebarItems: [],
            selectedThreadID: nil,
            threads: [],
            activeSidebarFilter: .all,
            selectionIsActive: false,
            selectedThreadIDs: []
        ).surface()

        XCTAssertEqual(surface.sidebar.bulkActions.map(\.kind), [.select])
        XCTAssertEqual(surface.sidebar.bulkActions.first?.isEnabled, false)
    }

    func testSavedFilterRestrictsVisibleRowsAndBulkAvailability() throws {
        let active = ChatThread(title: "Active")
        var pinned = ChatThread(title: "Pinned")
        pinned.isPinned = true
        var archived = ChatThread(title: "Archived")
        archived.isArchived = true
        let threads = [active, pinned, archived]

        let surface = WorkspaceNavigationSurfaceBuilder(
            projects: [],
            selectedProjectID: nil,
            sidebarItems: threads.map { SidebarItem(thread: $0) },
            selectedThreadID: active.id,
            threads: threads,
            activeSidebarFilter: .pinned,
            selectionIsActive: true,
            selectedThreadIDs: [active.id, pinned.id, archived.id]
        ).surface()

        XCTAssertEqual(surface.sidebar.activeFilter, .pinned)
        XCTAssertEqual(surface.sidebar.savedFilters.map(\.count), [3, 1, 1, 1])
        XCTAssertEqual(surface.sidebar.visibleItems.map(\.title), ["Pinned"])
        XCTAssertEqual(surface.sidebar.selectedThreadIDs, [pinned.id])
        XCTAssertEqual(surface.sidebar.selectionLabel, "1 chat selected")
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .selectAll }?.isEnabled, false)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .pin }?.isEnabled, false)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .unpin }?.isEnabled, true)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .unarchive }?.isEnabled, false)
    }

    func testSavedSearchRestrictsVisibleRowsAndBulkAvailability() throws {
        let searchID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let active = ChatThread(title: "Active")
        var matchingPinned = ChatThread(title: "Investigate flakes")
        matchingPinned.isPinned = true
        var matchingArchived = ChatThread(title: "Archived flaky CI")
        matchingArchived.isArchived = true
        let threads = [active, matchingPinned, matchingArchived]

        let surface = WorkspaceNavigationSurfaceBuilder(
            projects: [],
            selectedProjectID: nil,
            sidebarItems: threads.map { SidebarItem(thread: $0) },
            selectedThreadID: active.id,
            threads: threads,
            activeSidebarFilter: .all,
            activeSidebarSavedSearchID: searchID,
            sidebarSavedSearches: [
                SidebarSavedSearch(id: searchID, title: "Flaky CI", query: "flak")
            ],
            selectionIsActive: true,
            selectedThreadIDs: [active.id, matchingPinned.id, matchingArchived.id]
        ).surface()

        XCTAssertEqual(surface.sidebar.customSavedSearches.first?.isActive, true)
        XCTAssertEqual(surface.sidebar.visibleItems.map(\.title), ["Investigate flakes", "Archived flaky CI"])
        XCTAssertEqual(surface.sidebar.selectedThreadIDs, Set([matchingPinned.id, matchingArchived.id]))
        XCTAssertEqual(surface.sidebar.selectionLabel, "2 chats selected")
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .selectAll }?.isEnabled, false)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .pin }?.isEnabled, false)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .unpin }?.isEnabled, true)
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .unarchive }?.isEnabled, true)
    }
}
