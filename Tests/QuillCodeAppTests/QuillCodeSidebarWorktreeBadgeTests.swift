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
        XCTAssertEqual(summary.location, .worktree)
    }

    func testSidebarItemFlagsDanglingWorktreeBinding() {
        var thread = ChatThread(title: "Stale")
        thread.worktree = WorktreeBinding(path: "/does-not-exist-\(UUID().uuidString)", branch: "quill/gone")

        let summary = SidebarItem(thread: thread).worktree
        XCTAssertEqual(summary?.branchLeaf, "gone")
        XCTAssertEqual(summary?.isResolvable, false, "a removed worktree dir must surface as dangling")
    }

    func testSidebarItemLabelsDetachedManagedWorktree() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-detached-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var thread = ChatThread(title: "Managed task")
        thread.worktree = WorktreeBinding(path: dir.path, branch: "", base: "main")

        let summary = try XCTUnwrap(SidebarItem(thread: thread).worktree)

        XCTAssertEqual(summary.branch, "")
        XCTAssertEqual(summary.branchLeaf, "Detached")
        XCTAssertTrue(summary.isResolvable)
        XCTAssertEqual(summary.location, .worktree)
    }

    func testSidebarItemLabelsLocalExecutionAndKeepsWorktreeAssociation() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-local-handoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var thread = ChatThread(title: "Managed task")
        thread.worktree = WorktreeBinding(
            path: dir.path,
            branch: "",
            base: "main",
            location: .local
        )

        let summary = try XCTUnwrap(SidebarItem(thread: thread).worktree)

        XCTAssertEqual(summary.branchLeaf, "Local")
        XCTAssertEqual(summary.location, .local)
        XCTAssertTrue(summary.isResolvable)
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

    func testSidebarItemSurfaceCarriesAndRoundTripsPullRequestStatus() throws {
        var thread = ChatThread(title: "Land task")
        thread.pullRequest = PullRequestLink(
            number: 42,
            title: "Land task",
            url: "https://github.test/pull/42",
            status: .queued,
            baseBranch: "main",
            headBranch: "feature/land",
            headCommit: "abc123"
        )

        let surface = SidebarItemSurface(item: SidebarItem(thread: thread), selectedThreadID: thread.id)
        XCTAssertEqual(surface.pullRequest?.compactLabel, "PR #42 · Queued")

        let decoded = try JSONDecoder().decode(
            SidebarItemSurface.self,
            from: JSONEncoder().encode(surface)
        )
        XCTAssertEqual(decoded.pullRequest, thread.pullRequest)
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
        XCTAssertNil(decoded.pullRequest)
        XCTAssertNil(decoded.runStatusLabel)
    }

    func testSidebarItemSurfaceRoundTripsLiveRunStatus() throws {
        let item = SidebarItem(thread: ChatThread(title: "Background work"))
        let surface = SidebarItemSurface(
            item: item,
            selectedThreadID: nil,
            runStatusLabel: "Running tests"
        )

        let decoded = try JSONDecoder().decode(
            SidebarItemSurface.self,
            from: JSONEncoder().encode(surface)
        )

        XCTAssertEqual(decoded.runStatusLabel, "Running tests")
        XCTAssertTrue(decoded.isRunning)
    }

    func testLegacySidebarWorktreeSummaryDefaultsToWorktreeLocation() throws {
        let json = #"{"branch":"","branchLeaf":"Detached","isResolvable":true}"#

        let decoded = try JSONDecoder().decode(
            SidebarItemWorktreeSummary.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.location, .worktree)
    }
}
