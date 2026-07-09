import XCTest
import Foundation
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeSidebarWorktreeBadgeTests: XCTestCase {
    func testSidebarItemMapsResolvableWorktreeBinding() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wtbadge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var thread = ChatThread(title: "Feature work")
        thread.worktree = WorktreeBinding(path: dir.path, branch: "quill/add-login", base: "main")

        let summary = try XCTUnwrap(SidebarItem(thread: thread).worktree)
        XCTAssertEqual(summary.branch, "quill/add-login")
        XCTAssertEqual(summary.branchLeaf, "add-login", "the chip shows the branch's last segment")
        XCTAssertTrue(summary.isResolvable)
    }

    func testSidebarItemFlagsDanglingWorktreeBinding() {
        var thread = ChatThread(title: "Stale")
        thread.worktree = WorktreeBinding(path: "/does-not-exist-\(UUID().uuidString)", branch: "quill/gone")

        let summary = SidebarItem(thread: thread).worktree
        XCTAssertEqual(summary?.branchLeaf, "gone")
        XCTAssertEqual(summary?.isResolvable, false, "a removed worktree dir must surface as dangling")
    }

    func testSidebarItemHasNoWorktreeSummaryForAnUnboundThread() {
        XCTAssertNil(SidebarItem(thread: ChatThread(title: "Local")).worktree)
    }

    func testSidebarItemSurfaceCarriesAndRoundTripsWorktreeThroughCodable() throws {
        let summary = SidebarItemWorktreeSummary(branch: "quill/x", branchLeaf: "x", isResolvable: true)
        var item = SidebarItem(thread: ChatThread(title: "T"))
        item.worktree = summary
        let surface = SidebarItemSurface(item: item, selectedThreadID: nil)
        XCTAssertEqual(surface.worktree, summary)

        let decoded = try JSONDecoder().decode(
            SidebarItemSurface.self,
            from: JSONEncoder().encode(surface)
        )
        XCTAssertEqual(decoded.worktree, summary)
    }

    func testLegacySidebarItemSurfaceJSONWithoutWorktreeDecodesToNil() throws {
        // A surface persisted before the worktree field existed must still decode (worktree = nil).
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "subtitle": "trustedrouter/fast",
          "searchText": "",
          "actions": [],
          "isSelected": false,
          "isPinned": false,
          "isArchived": false
        }
        """
        let decoded = try JSONDecoder().decode(SidebarItemSurface.self, from: Data(json.utf8))
        XCTAssertNil(decoded.worktree)
    }
}
