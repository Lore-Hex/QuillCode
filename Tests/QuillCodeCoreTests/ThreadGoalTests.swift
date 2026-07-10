import XCTest
@testable import QuillCodeCore

final class ThreadGoalTests: XCTestCase {
    func testGoalNormalizesObjectiveAndTransitionsClearBlocker() throws {
        let createdAt = Date(timeIntervalSince1970: 10)
        let blockedAt = Date(timeIntervalSince1970: 20)
        let resumedAt = Date(timeIntervalSince1970: 30)
        let goal = try XCTUnwrap(ThreadGoal(
            objective: "  Ship a reliable release  ",
            createdAt: createdAt,
            updatedAt: createdAt
        ))

        XCTAssertEqual(goal.objective, "Ship a reliable release")
        XCTAssertEqual(goal.status, .active)

        let blocked = goal.updating(status: .blocked, blocker: "Waiting for CI", at: blockedAt)
        XCTAssertEqual(blocked.blocker, "Waiting for CI")
        XCTAssertEqual(blocked.updatedAt, blockedAt)

        let resumed = blocked.updating(status: .active, at: resumedAt)
        XCTAssertEqual(resumed.status, .active)
        XCTAssertNil(resumed.blocker)
        XCTAssertEqual(resumed.createdAt, createdAt)
        XCTAssertEqual(resumed.updatedAt, resumedAt)
    }

    func testGoalRejectsBlankObjectiveAndBoundsStoredText() throws {
        XCTAssertNil(ThreadGoal(objective: " \n "))

        let goal = try XCTUnwrap(ThreadGoal(
            objective: String(repeating: "g", count: ThreadGoal.maximumObjectiveLength + 100),
            status: .blocked,
            blocker: String(repeating: "b", count: ThreadGoal.maximumBlockerLength + 100)
        ))
        XCTAssertEqual(goal.objective.count, ThreadGoal.maximumObjectiveLength)
        XCTAssertEqual(goal.blocker?.count, ThreadGoal.maximumBlockerLength)
    }

    func testGoalDecodingRejectsBlankObjective() throws {
        let json = """
        {
          "objective": "   ",
          "status": "active",
          "createdAt": 0,
          "updatedAt": 0
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(ThreadGoal.self, from: Data(json.utf8)))
    }
}
