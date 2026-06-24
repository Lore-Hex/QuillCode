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
            selectionIsActive: false,
            selectedThreadIDs: []
        ).surface()

        XCTAssertEqual(surface.projects.items.map(\.name), ["Newer", "Older"])
        XCTAssertEqual(surface.projects.selectedProjectID, olderProject.id)
        XCTAssertEqual(surface.projects.items.map(\.isSelected), [false, true])
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
            selectionIsActive: false,
            selectedThreadIDs: []
        ).surface()

        XCTAssertEqual(surface.sidebar.bulkActions.map(\.kind), [.select])
        XCTAssertEqual(surface.sidebar.bulkActions.first?.isEnabled, false)
    }
}
