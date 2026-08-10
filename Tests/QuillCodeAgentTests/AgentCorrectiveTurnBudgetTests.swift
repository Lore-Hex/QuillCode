import XCTest
@testable import QuillCodeAgent

final class AgentCorrectiveTurnBudgetTests: XCTestCase {
    func testConsecutiveCorrectiveTurnsAreBoundedAcrossGateTypes() {
        var budget = AgentCorrectiveTurnBudget()

        for _ in 0..<AgentCorrectiveTurnBudget.limit {
            XCTAssertTrue(budget.beginCorrectiveTurn())
        }
        XCTAssertFalse(budget.beginCorrectiveTurn())
    }

    func testExecutedToolResetsCorrectiveTurnBudget() {
        var budget = AgentCorrectiveTurnBudget()

        XCTAssertTrue(budget.beginCorrectiveTurn())
        XCTAssertTrue(budget.beginCorrectiveTurn())
        budget.recordExecutedTool()

        XCTAssertEqual(budget.consecutiveTurns, 0)
        XCTAssertTrue(budget.beginCorrectiveTurn())
    }

    func testRoutePromotionGivesFallbackFreshCorrectionBudget() {
        var budget = AgentCorrectiveTurnBudget()
        XCTAssertTrue(budget.beginCorrectiveTurn())

        budget.recordRoutePromotion()

        XCTAssertEqual(budget.consecutiveTurns, 0)
        for _ in 0..<AgentCorrectiveTurnBudget.limit {
            XCTAssertTrue(budget.beginCorrectiveTurn())
        }
        XCTAssertFalse(budget.beginCorrectiveTurn())
    }
}
