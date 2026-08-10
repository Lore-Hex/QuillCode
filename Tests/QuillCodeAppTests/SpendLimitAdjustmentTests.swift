import XCTest
@testable import QuillCodeApp

final class SpendLimitAdjustmentTests: XCTestCase {
    func testIncreaseMovesThroughPredictableCurrencyPresets() {
        XCTAssertEqual(SpendLimitAdjustment.increasedLimit(current: 0.50, spentUSD: 0.10), 1)
        XCTAssertEqual(SpendLimitAdjustment.increasedLimit(current: 1, spentUSD: 0.28), 2)
        XCTAssertEqual(SpendLimitAdjustment.increasedLimit(current: 5, spentUSD: 4), 10)
    }

    func testIncreaseFromNoLimitChoosesAtLeastOneDollarAndClearsCurrentSpend() {
        XCTAssertEqual(SpendLimitAdjustment.increasedLimit(current: nil, spentUSD: 0.28), 1)
        XCTAssertEqual(SpendLimitAdjustment.increasedLimit(current: nil, spentUSD: 6), 10)
    }

    func testDecreaseNeverMovesBelowAlreadySpentAmount() {
        XCTAssertEqual(SpendLimitAdjustment.decreasedLimit(current: 2, spentUSD: 0.28), 1)
        XCTAssertEqual(SpendLimitAdjustment.decreasedLimit(current: 1, spentUSD: 0.28), 0.50)
        XCTAssertNil(SpendLimitAdjustment.decreasedLimit(current: 1, spentUSD: 0.80))
        XCTAssertFalse(SpendLimitAdjustment.canDecrease(current: 1, spentUSD: 0.80))
    }

    func testCustomAndLargeLimitsStillHaveUsefulAdjustments() {
        XCTAssertEqual(SpendLimitAdjustment.decreasedLimit(current: 3, spentUSD: 0.20), 2)
        XCTAssertEqual(SpendLimitAdjustment.increasedLimit(current: 100, spentUSD: 20), 200)
    }
}
