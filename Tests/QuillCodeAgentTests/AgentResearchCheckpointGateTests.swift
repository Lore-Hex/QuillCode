import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentResearchCheckpointGateTests: XCTestCase {
    func testRequiresExactDraftBeforeAnotherReadOnlyAction() throws {
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.correction(
            path: "outputs/revenue.html",
            proposedToolRisk: .read,
            canWriteFiles: true,
            correctionCounts: [:]
        ))

        XCTAssertEqual(correction.path, "outputs/revenue.html")
        XCTAssertTrue(correction.prompt.contains("host.file.write"))
        XCTAssertTrue(correction.prompt.contains("./outputs/revenue.html"))
        XCTAssertTrue(correction.prompt.contains("This is a checkpoint, not completion"))
    }

    func testDoesNotInterruptMutationOrRunWithoutWritableDeliverable() {
        XCTAssertNil(AgentResearchCheckpointGate.correction(
            path: "outputs/revenue.html",
            proposedToolRisk: .append,
            canWriteFiles: true,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchCheckpointGate.correction(
            path: nil,
            proposedToolRisk: .read,
            canWriteFiles: true,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchCheckpointGate.correction(
            path: "outputs/revenue.html",
            proposedToolRisk: .read,
            canWriteFiles: false,
            correctionCounts: [:]
        ))
    }

    func testCorrectionBudgetIsBounded() {
        XCTAssertNotNil(AgentResearchCheckpointGate.correction(
            path: "outputs/revenue.html",
            proposedToolRisk: .read,
            canWriteFiles: true,
            correctionCounts: ["outputs/revenue.html": 1]
        ))
        XCTAssertNil(AgentResearchCheckpointGate.correction(
            path: "outputs/revenue.html",
            proposedToolRisk: .read,
            canWriteFiles: true,
            correctionCounts: ["outputs/revenue.html": 2]
        ))
    }

    func testContinuationRequiresResearchBeforeFinalRewrite() throws {
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.continuationCorrection(
            path: "outputs/revenue.html",
            didResumeResearch: false,
            correctionCounts: [:]
        ))

        XCTAssertTrue(correction.prompt.contains("host.web.search"))
        XCTAssertTrue(correction.prompt.contains("host.web.fetch"))
        XCTAssertTrue(correction.prompt.contains("cannot complete the task"))
        XCTAssertTrue(correction.prompt.contains("./outputs/revenue.html"))
    }

    func testContinuationAfterResearchRequiresFinalRewriteAndIsBounded() throws {
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.continuationCorrection(
            path: "outputs/revenue.html",
            didResumeResearch: true,
            correctionCounts: ["outputs/revenue.html": 1]
        ))

        XCTAssertTrue(correction.prompt.contains("evidence gathered after the checkpoint"))
        XCTAssertNil(AgentResearchCheckpointGate.continuationCorrection(
            path: "outputs/revenue.html",
            didResumeResearch: true,
            correctionCounts: ["outputs/revenue.html": 2]
        ))
    }
}
