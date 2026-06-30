import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceNavigationHistoryTests: XCTestCase {
    func testHistoryDropsForwardEntriesAfterNewTransition() {
        let first = WorkspaceNavigationLocation(threadID: UUID())
        let second = WorkspaceNavigationLocation(threadID: UUID())
        let third = WorkspaceNavigationLocation(projectID: UUID())
        var history = WorkspaceNavigationHistoryState()

        history.recordTransition(from: first, to: second)
        XCTAssertEqual(history.entries, [first, second])
        XCTAssertTrue(history.canGoBack)
        XCTAssertEqual(history.goBack(), first)
        XCTAssertTrue(history.canGoForward)

        history.recordTransition(from: first, to: third)

        XCTAssertEqual(history.entries, [first, third])
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.goBack(), first)
    }

    func testHistoryPrunesDeletedLocationsWithoutLeavingInvalidIndex() {
        let firstThreadID = UUID()
        let secondThreadID = UUID()
        let projectID = UUID()
        var history = WorkspaceNavigationHistoryState(entries: [
            WorkspaceNavigationLocation(threadID: firstThreadID),
            WorkspaceNavigationLocation(threadID: secondThreadID),
            WorkspaceNavigationLocation(projectID: projectID)
        ], currentIndex: 2)

        history.prune(validThreadIDs: [firstThreadID], validProjectIDs: [])

        XCTAssertEqual(history.entries, [WorkspaceNavigationLocation(threadID: firstThreadID)])
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testHistoryCapsEntriesForLongSessions() {
        let locations = (0..<(WorkspaceNavigationHistoryState.maximumEntryCount + 12))
            .map { _ in WorkspaceNavigationLocation(threadID: UUID()) }
        var history = WorkspaceNavigationHistoryState()

        for index in 1..<locations.count {
            history.recordTransition(from: locations[index - 1], to: locations[index])
        }

        XCTAssertEqual(history.entries.count, WorkspaceNavigationHistoryState.maximumEntryCount)
        XCTAssertEqual(history.entries.first, locations[locations.count - WorkspaceNavigationHistoryState.maximumEntryCount])
        XCTAssertEqual(history.entries.last, locations.last)
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testWorkspaceModelNavigatesAcrossThreads() {
        let firstProject = ProjectRef(name: "First", path: "/tmp/first")
        let secondProject = ProjectRef(name: "Second", path: "/tmp/second")
        let firstThread = ChatThread(title: "First thread", projectID: firstProject.id)
        let secondThread = ChatThread(title: "Second thread", projectID: secondProject.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [firstProject, secondProject],
            selectedProjectID: firstProject.id,
            threads: [firstThread, secondThread],
            selectedThreadID: firstThread.id
        ))

        model.selectThread(secondThread.id)

        XCTAssertEqual(model.root.selectedThreadID, secondThread.id)
        XCTAssertTrue(model.navigationHistory.canGoBack)
        XCTAssertFalse(model.navigationHistory.canGoForward)

        XCTAssertTrue(model.navigateBackInWorkspace())
        XCTAssertEqual(model.root.selectedThreadID, firstThread.id)
        XCTAssertEqual(model.root.selectedProjectID, firstProject.id)
        XCTAssertTrue(model.navigationHistory.canGoForward)

        XCTAssertTrue(model.navigateForwardInWorkspace())
        XCTAssertEqual(model.root.selectedThreadID, secondThread.id)
        XCTAssertEqual(model.root.selectedProjectID, secondProject.id)
    }

    func testWorkspaceModelPrunesDeletedThreadFromHistory() {
        let firstThread = ChatThread(title: "First")
        let secondThread = ChatThread(title: "Second")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [firstThread, secondThread],
            selectedThreadID: firstThread.id
        ))
        model.selectThread(secondThread.id)

        XCTAssertTrue(model.deleteThread(firstThread.id))

        XCTAssertFalse(model.navigateBackInWorkspace())
        XCTAssertEqual(model.root.selectedThreadID, secondThread.id)
        XCTAssertFalse(model.navigationHistory.entries.contains(
            WorkspaceNavigationLocation(threadID: firstThread.id)
        ))
    }
}
