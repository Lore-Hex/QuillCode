import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceThreadSelectionTests: XCTestCase {
    func testAdjacentSelectionWrapsInBothDirections() {
        let newest = ChatThread(title: "Newest")
        let middle = ChatThread(title: "Middle")
        let oldest = ChatThread(title: "Oldest")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [newest, middle, oldest],
            selectedThreadID: nil
        ))
        let orderedIDs = model.filteredSidebarItems().map(\.id)
        model.root.selectedThreadID = orderedIDs.first

        XCTAssertTrue(model.selectAdjacentSidebarThread(offset: -1))
        XCTAssertEqual(model.root.selectedThreadID, orderedIDs.last)
        XCTAssertTrue(model.selectAdjacentSidebarThread(offset: 1))
        XCTAssertEqual(model.root.selectedThreadID, orderedIDs.first)
    }

    func testAdjacentSelectionStartsAtNearestEdgeWhenNothingIsSelected() {
        let newest = ChatThread(title: "Newest")
        let oldest = ChatThread(title: "Oldest")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [newest, oldest],
            selectedThreadID: nil
        ))
        let orderedIDs = model.filteredSidebarItems().map(\.id)

        XCTAssertTrue(model.selectAdjacentSidebarThread(offset: 1))
        XCTAssertEqual(model.root.selectedThreadID, orderedIDs.first)

        model.root.selectedThreadID = nil
        XCTAssertTrue(model.selectAdjacentSidebarThread(offset: -1))
        XCTAssertEqual(model.root.selectedThreadID, orderedIDs.last)
    }

    func testAdjacentSelectionDoesNothingAtASelectedSingleThread() {
        let only = ChatThread(title: "Only")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [only],
            selectedThreadID: only.id
        ))

        XCTAssertFalse(model.selectAdjacentSidebarThread(offset: 1))
        XCTAssertEqual(model.root.selectedThreadID, only.id)
    }
}
