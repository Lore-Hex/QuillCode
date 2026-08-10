import XCTest
@testable import QuillCodeAgent

final class AgentCorrectiveTurnBudgetTests: XCTestCase {
    func testRepeatedCorrectiveTurnsAreBoundedWithinOneGate() {
        var budget = AgentCorrectiveTurnBudget()

        for _ in 0..<AgentCorrectiveTurnBudget.limit {
            XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "artifact-refresh"))
        }
        XCTAssertFalse(budget.beginCorrectiveTurn(correctionID: "artifact-refresh"))
    }

    func testDistinctCorrectivePhasesDoNotConsumeEachOthersLocalBudget() {
        var budget = AgentCorrectiveTurnBudget()

        XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "shell-path-1"))
        XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "shell-path-2"))
        XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "checkpoint-continuation"))
        XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "artifact-refresh"))
        XCTAssertEqual(budget.consecutiveTurns, 1)
        XCTAssertEqual(budget.aggregateTurns, 4)
    }

    func testDistinctCorrectivePhasesRemainAggregateBounded() {
        var budget = AgentCorrectiveTurnBudget()

        for index in 0..<AgentCorrectiveTurnBudget.aggregateLimit {
            XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "phase-\(index)"))
        }
        XCTAssertFalse(budget.beginCorrectiveTurn(correctionID: "one-more-phase"))
    }

    func testExecutedToolResetsCorrectiveTurnBudget() {
        var budget = AgentCorrectiveTurnBudget()

        XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "refresh"))
        XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "refresh"))
        budget.recordExecutedTool()

        XCTAssertEqual(budget.consecutiveTurns, 0)
        XCTAssertEqual(budget.aggregateTurns, 0)
        XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "refresh"))
    }

    func testRoutePromotionGivesFallbackFreshCorrectionBudget() {
        var budget = AgentCorrectiveTurnBudget()
        XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "audit"))

        budget.recordRoutePromotion()

        XCTAssertEqual(budget.consecutiveTurns, 0)
        XCTAssertEqual(budget.aggregateTurns, 0)
        for _ in 0..<AgentCorrectiveTurnBudget.limit {
            XCTAssertTrue(budget.beginCorrectiveTurn(correctionID: "audit"))
        }
        XCTAssertFalse(budget.beginCorrectiveTurn(correctionID: "audit"))
    }
}
