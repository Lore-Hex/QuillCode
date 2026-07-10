import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceThreadGoalEngineTests: XCTestCase {
    func testLifecyclePreservesObjectiveAndRecordsBlocker() throws {
        let startedAt = Date(timeIntervalSince1970: 10)
        let blockedAt = Date(timeIntervalSince1970: 20)
        let completedAt = Date(timeIntervalSince1970: 30)
        let started = WorkspaceThreadGoalEngine.apply(.set("Ship QuillCode"), to: nil, now: startedAt)
        guard case .replace(let startedGoal?) = started.mutation else {
            return XCTFail("Expected a started goal")
        }

        let blocked = WorkspaceThreadGoalEngine.apply(
            .block("Waiting for release signing"),
            to: startedGoal,
            now: blockedAt
        )
        guard case .replace(let blockedGoal?) = blocked.mutation else {
            return XCTFail("Expected a blocked goal")
        }
        XCTAssertEqual(blockedGoal.status, .blocked)
        XCTAssertEqual(blockedGoal.blocker, "Waiting for release signing")
        XCTAssertEqual(blockedGoal.createdAt, startedAt)

        let completed = WorkspaceThreadGoalEngine.apply(.complete, to: blockedGoal, now: completedAt)
        guard case .replace(let completedGoal?) = completed.mutation else {
            return XCTFail("Expected a completed goal")
        }
        XCTAssertEqual(completedGoal.status, .completed)
        XCTAssertNil(completedGoal.blocker)
        XCTAssertEqual(completedGoal.updatedAt, completedAt)
    }

    func testMissingGoalActionsAreNoOpsWithGuidance() {
        for request in [
            WorkspaceThreadGoalRequest.complete,
            .block("Waiting"),
            .resume,
            .clear
        ] {
            let outcome = WorkspaceThreadGoalEngine.apply(request, to: nil)
            XCTAssertEqual(outcome.mutation, .unchanged)
            XCTAssertTrue(outcome.assistantText.contains("/goal objective"))
        }
    }
}
