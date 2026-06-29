import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceSidebarIntegrationTests: XCTestCase {
    func testBulkSelectionArchivesAndDeletesChats() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let first = ChatThread(title: "Run whoami", projectID: project.id)
        let second = ChatThread(title: "Check diff", projectID: project.id)
        let fallback = ChatThread(title: "Review tests", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [first, second, fallback],
            selectedThreadID: first.id
        ))

        model.startSidebarSelection(selecting: first.id)
        model.toggleSidebarThreadSelection(second.id)

        var surface = model.surface()
        XCTAssertTrue(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectionLabel, "2 chats selected")
        XCTAssertEqual(Set(surface.sidebar.items.filter(\.isBulkSelected).map(\.id)), [first.id, second.id])
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .archive }?.isEnabled, true)

        XCTAssertTrue(model.performSidebarBulkAction(.archive))
        surface = model.surface()

        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(Set(surface.sidebar.archivedItems.map(\.id)), [first.id, second.id])
        XCTAssertEqual(surface.sidebar.selectedThreadID, fallback.id)

        model.selectAllSidebarThreads()
        surface = model.surface()
        XCTAssertEqual(surface.sidebar.selectionLabel, "3 chats selected")
        XCTAssertTrue(model.performSidebarBulkAction(.delete))

        surface = model.surface()
        XCTAssertEqual(surface.sidebar.items.count, 0)
        XCTAssertNil(surface.sidebar.selectedThreadID)
        XCTAssertFalse(surface.sidebar.isSelectionMode)
    }

    func testSavedFilterClearsSelectionAndSelectAllUsesVisibleRows() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let recent = ChatThread(title: "Recent", projectID: project.id)
        var pinned = ChatThread(title: "Pinned", projectID: project.id)
        pinned.isPinned = true
        var archived = ChatThread(title: "Archived", projectID: project.id)
        archived.isArchived = true
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [recent, pinned, archived],
            selectedThreadID: recent.id
        ))

        model.startSidebarSelection(selecting: recent.id)
        XCTAssertEqual(model.selectedSidebarThreadIDs(), [recent.id])

        model.setSidebarFilter(.archived)
        var surface = model.surface()
        XCTAssertEqual(surface.sidebar.activeFilter, .archived)
        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.visibleItems.map(\.title), ["Archived"])

        model.selectAllSidebarThreads()
        surface = model.surface()
        XCTAssertTrue(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectedThreadIDs, [archived.id])
        XCTAssertEqual(surface.sidebar.selectionLabel, "1 chat selected")

        XCTAssertTrue(model.runWorkspaceCommand("sidebar-filter:pinned", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        surface = model.surface()
        XCTAssertEqual(surface.sidebar.activeFilter, .pinned)
        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.visibleItems.map(\.title), ["Pinned"])
    }

    func testSavedSearchCommandClearsSelectionAndSelectAllUsesMatchingRows() throws {
        let searchID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let active = ChatThread(title: "Active", projectID: project.id)
        var matchingPinned = ChatThread(title: "Investigate flakes", projectID: project.id)
        matchingPinned.isPinned = true
        var matchingArchived = ChatThread(title: "Archived flaky CI", projectID: project.id)
        matchingArchived.isArchived = true
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [active, matchingPinned, matchingArchived],
                selectedThreadID: active.id
            ),
            sidebarSavedSearches: [
                SidebarSavedSearch(id: searchID, title: "Flaky CI", query: "flak")
            ]
        )

        model.startSidebarSelection(selecting: active.id)
        XCTAssertEqual(model.selectedSidebarThreadIDs(), [active.id])

        XCTAssertTrue(model.runWorkspaceCommand(
            "sidebar-saved-search:\(searchID.uuidString)",
            workspaceRoot: URL(fileURLWithPath: "/tmp")
        ))
        var surface = model.surface()
        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.customSavedSearches.first?.isActive, true)
        XCTAssertEqual(surface.sidebar.visibleItems.map(\.title), ["Investigate flakes", "Archived flaky CI"])

        model.selectAllSidebarThreads()
        surface = model.surface()
        XCTAssertTrue(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectedThreadIDs, Set([matchingPinned.id, matchingArchived.id]))
        XCTAssertEqual(surface.sidebar.selectionLabel, "2 chats selected")

        model.setSidebarFilter(.recent)
        surface = model.surface()
        XCTAssertEqual(surface.sidebar.activeFilter, .recent)
        XCTAssertEqual(surface.sidebar.customSavedSearches.first?.isActive, false)
        XCTAssertEqual(surface.sidebar.visibleItems.map(\.title), ["Active"])
    }
}
