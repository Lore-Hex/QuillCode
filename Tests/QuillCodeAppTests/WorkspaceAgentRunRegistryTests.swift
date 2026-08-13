import XCTest
@testable import QuillCodeApp

final class WorkspaceAgentRunRegistryTests: XCTestCase {
    func testTracksIndependentThreadStatusesAndFinishesOneWithoutTouchingAnother() {
        let first = UUID()
        let second = UUID()
        var registry = WorkspaceAgentRunRegistry()

        XCTAssertTrue(registry.begin(threadID: first, status: "Running"))
        XCTAssertTrue(registry.begin(threadID: second, status: "Queued"))
        registry.update(threadID: first, status: "Streaming")

        XCTAssertEqual(registry.activeThreadIDs, [first, second])
        XCTAssertEqual(registry.status(for: first), "Streaming")
        XCTAssertEqual(registry.status(for: second), "Queued")

        XCTAssertEqual(registry.finish(threadID: first), "Streaming")
        XCTAssertFalse(registry.isRunning(first))
        XCTAssertTrue(registry.isRunning(second))
        XCTAssertEqual(registry.activeCount, 1)
    }

    func testUnknownUpdateCannotCreatePhantomRun() {
        var registry = WorkspaceAgentRunRegistry()
        registry.update(threadID: UUID(), status: "Streaming")
        XCTAssertTrue(registry.activeThreadIDs.isEmpty)
    }

    func testFinishAllReportsWhetherWorkExisted() {
        var registry = WorkspaceAgentRunRegistry()
        XCTAssertFalse(registry.finishAll())
        registry.begin(threadID: UUID(), status: "Running")
        XCTAssertTrue(registry.finishAll())
        XCTAssertTrue(registry.activeThreadIDs.isEmpty)
    }

    func testStaleGenerationCannotUpdateOrFinishReplacementRun() {
        let threadID = UUID()
        let firstRunID = UUID()
        let replacementRunID = UUID()
        var registry = WorkspaceAgentRunRegistry()

        registry.begin(threadID: threadID, runID: firstRunID, status: "First")
        registry.begin(threadID: threadID, runID: replacementRunID, status: "Replacement")
        registry.update(threadID: threadID, runID: firstRunID, status: "Stale update")

        XCTAssertEqual(registry.runID(for: threadID), replacementRunID)
        XCTAssertEqual(registry.status(for: threadID), "Replacement")
        XCTAssertNil(registry.finish(threadID: threadID, runID: firstRunID))
        XCTAssertTrue(registry.isRunning(threadID, runID: replacementRunID))
    }
}
