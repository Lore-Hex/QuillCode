import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentResearchRefreshGateTests: XCTestCase {
    func testRefreshRewritesStaleArtifactAsCompleteDeliverable() throws {
        let correction = try XCTUnwrap(AgentResearchRefreshGate.correction(
            stalePaths: ["outputs/travel-policy.md"],
            correctionCounts: [:]
        ))

        XCTAssertEqual(correction.path, "outputs/travel-policy.md")
        XCTAssertTrue(correction.prompt.contains("complete current deliverable"))
        XCTAssertTrue(correction.prompt.contains("exact source URLs"))
        XCTAssertTrue(correction.prompt.contains("Resolve every evidence gap"))
        XCTAssertTrue(correction.prompt.contains("Remove TODO, pending, draft"))
        XCTAssertTrue(correction.prompt.contains("future-work language"))
        XCTAssertTrue(correction.prompt.contains("read ./outputs/travel-policy.md back"))
    }

    func testRefreshBeforeLocalReadRequiresWriteAccessAndStaleArtifact() {
        XCTAssertNotNil(AgentResearchRefreshGate.correctionBeforeNonResearchRead(
            stalePaths: ["outputs/travel-policy.md"],
            proposedToolName: ToolDefinition.fileRead.name,
            proposedToolRisk: .read,
            canWriteFiles: true,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchRefreshGate.correctionBeforeNonResearchRead(
            stalePaths: ["outputs/travel-policy.md"],
            proposedToolName: ToolDefinition.fileRead.name,
            proposedToolRisk: .read,
            canWriteFiles: false,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchRefreshGate.correctionBeforeNonResearchRead(
            stalePaths: [],
            proposedToolName: ToolDefinition.fileRead.name,
            proposedToolRisk: .read,
            canWriteFiles: true,
            correctionCounts: [:]
        ))
    }

    func testRefreshDoesNotInterruptAdditionalResearchAndIsBounded() {
        XCTAssertNil(AgentResearchRefreshGate.correctionBeforeNonResearchRead(
            stalePaths: ["outputs/travel-policy.md"],
            proposedToolName: ToolDefinition.webFetch.name,
            proposedToolRisk: .read,
            canWriteFiles: true,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchRefreshGate.correction(
            stalePaths: ["outputs/travel-policy.md"],
            correctionCounts: [
                "outputs/travel-policy.md": AgentResearchRefreshGate.correctionLimitPerPath,
            ]
        ))
    }
}
