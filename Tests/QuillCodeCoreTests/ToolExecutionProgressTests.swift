import XCTest
@testable import QuillCodeCore

final class ToolExecutionProgressTests: XCTestCase {
    func testFractionCompletedUsesProviderUnitsAndClampsForPresentation() {
        XCTAssertEqual(ToolExecutionProgress(completed: 25, total: 100).fractionCompleted, 0.25)
        XCTAssertEqual(ToolExecutionProgress(completed: -10, total: 100).fractionCompleted, 0)
        XCTAssertEqual(ToolExecutionProgress(completed: 125, total: 100).fractionCompleted, 1)
    }

    func testFractionCompletedRequiresFinitePositiveTotal() {
        XCTAssertNil(ToolExecutionProgress(completed: 1).fractionCompleted)
        XCTAssertNil(ToolExecutionProgress(completed: 1, total: 0).fractionCompleted)
        XCTAssertNil(ToolExecutionProgress(completed: 1, total: -.infinity).fractionCompleted)
        XCTAssertNil(ToolExecutionProgress(completed: .infinity, total: 10).fractionCompleted)
    }

    func testProgressPayloadRoundTripsExactToolIdentity() throws {
        let payload = ToolProgressEventPayload(
            toolCallID: "tool-17",
            progress: ToolExecutionProgress(completed: 7, total: 9, message: "Indexing")
        )

        let decoded = try JSONHelpers.decode(
            ToolProgressEventPayload.self,
            from: JSONHelpers.encodePretty(payload)
        )

        XCTAssertEqual(decoded, payload)
    }
}
