import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AutoReviewCircuitBreakerTests: XCTestCase {
    func testThreeConsecutiveDenialsTripCircuit() {
        var circuit = AutoReviewCircuitBreaker()
        XCTAssertNil(circuit.record(.denied))
        XCTAssertNil(circuit.record(.denied))
        XCTAssertEqual(circuit.record(.denied), .consecutiveDenials(count: 3))
    }

    func testNonDenialResetsConsecutiveCount() {
        var circuit = AutoReviewCircuitBreaker()
        XCTAssertNil(circuit.record(.denied))
        XCTAssertNil(circuit.record(.timedOut))
        XCTAssertNil(circuit.record(.denied))
        XCTAssertNil(circuit.record(.denied))
        XCTAssertEqual(circuit.consecutiveDenials, 2)
    }

    func testTenDenialsInFiftyReviewsTripRollingCircuit() {
        var circuit = AutoReviewCircuitBreaker()
        for _ in 0..<9 {
            XCTAssertNil(circuit.record(.denied))
            XCTAssertNil(circuit.record(.approved))
        }
        XCTAssertEqual(
            circuit.record(.denied),
            .rollingDenials(count: 10, reviews: 19)
        )
    }
}
