import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentResearchCheckpointGateTests: XCTestCase {
    func testEarlyDelegationBlocksAnotherSerialFetchBeforeDraft() throws {
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.earlyDelegationCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.webFetch.name,
            canDelegate: true,
            canWriteFiles: true,
            hasDelegatedResearch: false,
            correctionCounts: [:]
        ))

        XCTAssertEqual(correction.path, "outputs/revenue.html")
        XCTAssertTrue(correction.prompt.contains("host.subagents.run now"))
        XCTAssertTrue(correction.prompt.contains("exact source URLs"))
        XCTAssertTrue(correction.prompt.contains("promise to continue is not a completed"))
    }

    func testEarlyDelegationRequiresToolsAndStopsAfterSuccessfulBatch() {
        XCTAssertNil(AgentResearchCheckpointGate.earlyDelegationCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.fileRead.name,
            canDelegate: true,
            canWriteFiles: true,
            hasDelegatedResearch: false,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchCheckpointGate.earlyDelegationCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.webSearch.name,
            canDelegate: false,
            canWriteFiles: true,
            hasDelegatedResearch: false,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchCheckpointGate.earlyDelegationCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.browserScript.name,
            canDelegate: true,
            canWriteFiles: true,
            hasDelegatedResearch: false,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchCheckpointGate.earlyDelegationCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.webSearch.name,
            canDelegate: true,
            canWriteFiles: true,
            hasDelegatedResearch: true,
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchCheckpointGate.earlyDelegationCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.webFetch.name,
            canDelegate: true,
            canWriteFiles: true,
            hasDelegatedResearch: false,
            hasSubstantialStructuredDirectEvidence: true,
            correctionCounts: [:]
        ))
    }

    func testVisibleBrowserExtractionCountsAsDirectResearch() {
        XCTAssertTrue(AgentResearchCheckpointGate.isDirectResearchCollectionTool(
            ToolDefinition.browserOpen.name
        ))
        XCTAssertTrue(AgentResearchCheckpointGate.isDirectResearchCollectionTool(
            ToolDefinition.browserInspect.name
        ))
        XCTAssertTrue(AgentResearchCheckpointGate.isDirectResearchCollectionTool(
            ToolDefinition.browserScript.name
        ))
        XCTAssertFalse(AgentResearchCheckpointGate.isDirectResearchCollectionTool(
            ToolDefinition.browserClick.name
        ))
        XCTAssertFalse(AgentResearchCheckpointGate.isParallelizableResearchCollectionTool(
            ToolDefinition.browserScript.name
        ))
    }

    func testShellWebFetchAndDownloadedPageParsingCountAsDirectResearch() {
        let curl = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "curl -s https://example.gov/data -o downloads/data.html",
            ])
        )
        let parse = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "sed -n '1,80p' downloads/data.html",
            ])
        )
        let localRead = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "cat inputs/records.csv"])
        )

        XCTAssertTrue(AgentResearchCheckpointGate.isDirectResearchCollectionCall(curl))
        XCTAssertTrue(AgentResearchCheckpointGate.isDirectResearchCollectionCall(parse))
        XCTAssertFalse(AgentResearchCheckpointGate.isDirectResearchCollectionCall(localRead))
    }

    func testCheckpointInterruptsShellResearchDespiteDestructiveToolRisk() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "grep -n Annual downloads/official-series.html",
            ])
        )
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.correction(
            path: "outputs/report.md",
            proposedToolName: call.name,
            proposedCall: call,
            proposedToolRisk: .destructive,
            canWriteFiles: true,
            correctionCounts: [:]
        ))

        XCTAssertEqual(correction.path, "outputs/report.md")
    }

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

    func testCheckpointInterruptsBrowserScriptDespiteAppendRisk() throws {
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.correction(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.browserScript.name,
            proposedToolRisk: .append,
            canWriteFiles: true,
            correctionCounts: [:]
        ))

        XCTAssertEqual(correction.path, "outputs/revenue.html")
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

    func testPostCheckpointResearchBudgetForcesFinalSynthesisBeforeAnotherRead() throws {
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.finalizationCorrection(
            path: "outputs/revenue.html",
            proposedToolRisk: .read,
            canWriteFiles: true,
            userMessage: "Create one row per company and cite every source URL.",
            correctionCounts: [:]
        ))

        XCTAssertTrue(correction.prompt.contains("post-checkpoint research budget"))
        XCTAssertTrue(correction.prompt.contains("complete final artifact"))
        XCTAssertTrue(correction.prompt.contains("do not leave TBD"))
        XCTAssertTrue(correction.prompt.contains("treat that draft as disposable"))
        XCTAssertTrue(correction.prompt.contains("row and column shape"))
        XCTAssertTrue(correction.prompt.contains("Create one row per company"))
        XCTAssertTrue(correction.prompt.contains("host.file.write"))
    }

    func testPostCheckpointSynthesisDoesNotInterruptWritesAndIsBounded() {
        XCTAssertEqual(AgentResearchCheckpointGate.finalizationCorrectionLimitPerPath, 2)
        XCTAssertNil(AgentResearchCheckpointGate.finalizationCorrection(
            path: "outputs/revenue.html",
            proposedToolRisk: .append,
            canWriteFiles: true,
            userMessage: "Create the report.",
            correctionCounts: [:]
        ))
        XCTAssertNil(AgentResearchCheckpointGate.finalizationCorrection(
            path: "outputs/revenue.html",
            proposedToolRisk: .read,
            canWriteFiles: true,
            userMessage: "Create the report.",
            correctionCounts: [
                "outputs/revenue.html":
                    AgentResearchCheckpointGate.finalizationCorrectionLimitPerPath,
            ]
        ))
    }

    func testPostCheckpointSynthesisInterruptsBrowserScriptDespiteAppendRisk() throws {
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.finalizationCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.browserScript.name,
            proposedToolRisk: .append,
            canWriteFiles: true,
            userMessage: "Create the report.",
            correctionCounts: [:]
        ))

        XCTAssertEqual(correction.path, "outputs/revenue.html")
    }

    func testExhaustedResearchBudgetBlocksAnotherFetch() throws {
        let correction = try XCTUnwrap(AgentResearchCheckpointGate.exhaustionCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.webFetch.name,
            canWriteFiles: true,
            userMessage: "Create an inline SVG chart with exact source URLs.",
            correctionCounts: [:]
        ))

        XCTAssertTrue(correction.prompt.contains("budget for this deliverable is exhausted"))
        XCTAssertTrue(correction.prompt.contains("Do not search"))
        XCTAssertTrue(correction.prompt.contains("self-contained visual"))
        XCTAssertTrue(correction.prompt.contains("Create an inline SVG chart"))
        XCTAssertTrue(correction.prompt.contains("host.file.write"))
        XCTAssertNil(AgentResearchCheckpointGate.exhaustionCorrection(
            path: "outputs/revenue.html",
            proposedToolName: ToolDefinition.fileRead.name,
            canWriteFiles: true,
            userMessage: "Create the report.",
            correctionCounts: [:]
        ))
    }

    func testPostDraftResearchBudgetFitsDesktopRun() {
        XCTAssertEqual(AgentResearchCheckpointGate.maximumPostDraftResearchWeight, 15)
    }

    func testRepeatedDelegationCorrectionRequiresExistingArtifactSynthesis() {
        let correction = AgentResearchCheckpointGate.repeatedDelegationCorrection(
            path: "outputs/revenue.html"
        )

        XCTAssertEqual(correction.path, "outputs/revenue.html")
        XCTAssertTrue(correction.prompt.contains("Do not launch another delegated batch"))
        XCTAssertTrue(correction.prompt.contains("host.file.write"))
        XCTAssertTrue(correction.prompt.contains("read the rewritten artifact back"))
    }
}
