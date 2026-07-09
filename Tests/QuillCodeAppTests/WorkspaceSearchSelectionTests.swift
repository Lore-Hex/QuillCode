import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSearchSelectionTests: XCTestCase {
    func testReconcileSelectsPreferredVisibleThread() {
        var selection = WorkspaceSearchSelection()
        let first = item(title: "First")
        let second = item(title: "Second")

        selection.reconcile(with: [first, second], preferredID: second.id)

        XCTAssertEqual(selection.highlightedThreadID, second.id)
    }

    func testReconcileSelectsFirstResultWhenPreferredIsMissing() {
        var selection = WorkspaceSearchSelection()
        let first = item(title: "First")
        let second = item(title: "Second")

        selection.reconcile(with: [first, second], preferredID: UUID())

        XCTAssertEqual(selection.highlightedThreadID, first.id)
    }

    func testReconcilePreservesVisibleHighlightAcrossQueryChanges() {
        var selection = WorkspaceSearchSelection()
        let first = item(title: "First")
        let second = item(title: "Second")
        selection.reconcile(with: [first, second])
        selection.move(by: 1, in: [first, second])

        selection.reconcile(with: [second, item(title: "Third")])

        XCTAssertEqual(selection.highlightedThreadID, second.id)
    }

    func testReconcileFallsBackWhenHighlightDisappears() {
        var selection = WorkspaceSearchSelection()
        let first = item(title: "First")
        let second = item(title: "Second")
        let third = item(title: "Third")
        selection.reconcile(with: [first, second])
        selection.move(by: 1, in: [first, second])

        selection.reconcile(with: [third])

        XCTAssertEqual(selection.highlightedThreadID, third.id)
    }

    func testMoveWrapsInBothDirections() {
        var selection = WorkspaceSearchSelection()
        let first = item(title: "First")
        let second = item(title: "Second")
        let third = item(title: "Third")
        let items = [first, second, third]
        selection.reconcile(with: items)

        selection.move(by: -1, in: items)
        XCTAssertEqual(selection.highlightedThreadID, third.id)

        selection.move(by: 1, in: items)
        XCTAssertEqual(selection.highlightedThreadID, first.id)
    }

    func testSelectedItemFallsBackToFirstResultIfHighlightIsStale() {
        var selection = WorkspaceSearchSelection()
        let first = item(title: "First")
        let second = item(title: "Second")
        selection.reconcile(with: [first])

        XCTAssertEqual(selection.selectedItem(in: [second])?.id, second.id)
    }

    func testSelectionClearsWhenNoResultsRemain() {
        var selection = WorkspaceSearchSelection()
        selection.reconcile(with: [item(title: "First")])

        selection.reconcile(with: [])

        XCTAssertNil(selection.highlightedThreadID)
        XCTAssertNil(selection.selectedItem(in: []))
    }

    func testExplicitSelectionRecordsClickedResult() {
        var selection = WorkspaceSearchSelection()
        let clicked = item(title: "Clicked")

        selection.select(clicked)

        XCTAssertEqual(selection.highlightedThreadID, clicked.id)
    }

    private func item(title: String) -> SidebarItemSurface {
        SidebarItemSurface(
            item: SidebarItem(thread: ChatThread(title: title)),
            selectedThreadID: nil
        )
    }
}
