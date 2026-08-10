import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentArtifactContractAuditGateTests: XCTestCase {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-contract-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testRecognizesExplicitMachineCheckableArtifactContract() {
        XCTAssertTrue(AgentArtifactContractAuditGate.requiresAudit(
            in: "The table must have exactly four company rows. The first five cells in every row must be ordered."
        ))
        XCTAssertTrue(AgentArtifactContractAuditGate.requiresAudit(
            in: "Put every company in the same <tr> as its values."
        ))
        XCTAssertTrue(AgentArtifactContractAuditGate.requiresAudit(
            in: "Restate every nominal revenue row with the selected CPI basis."
        ))
        XCTAssertTrue(AgentArtifactContractAuditGate.requiresAudit(
            in: "Run a deterministic post-write validator against the report."
        ))
        XCTAssertFalse(AgentArtifactContractAuditGate.requiresAudit(
            in: "Create a polished comparison report with a useful table."
        ))
    }

    func testOnlyValidatorCommandsAuditTheReferencedArtifact() {
        let path = "outputs/report.html"
        let readback = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "cat outputs/report.html"])
        )
        XCTAssertTrue(AgentArtifactContractAuditGate.auditedPaths(
            for: readback,
            among: [path]
        ).isEmpty)

        let echoedAssertion = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "echo 'assert outputs/report.html is valid'",
            ])
        )
        XCTAssertTrue(AgentArtifactContractAuditGate.auditedPaths(
            for: echoedAssertion,
            among: [path]
        ).isEmpty)

        let unrelated = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert open('inputs/source.csv').read()\"",
            ])
        )
        XCTAssertTrue(AgentArtifactContractAuditGate.auditedPaths(
            for: unrelated,
            among: [path]
        ).isEmpty)

        let validator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert open('outputs/report.html').read().count('<tr>') == 4\"",
            ])
        )
        XCTAssertEqual(AgentArtifactContractAuditGate.auditedPaths(
            for: validator,
            among: [path]
        ), [path])
    }

    func testValidatorScriptWithDescriptiveUnderscoreNameAuditsArtifact() {
        let path = "outputs/report.md"
        let validator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 scripts/check_deliverable.py outputs/report.md",
            ])
        )

        XCTAssertEqual(
            AgentArtifactContractAuditGate.auditedPaths(for: validator, among: [path]),
            [path]
        )
    }

    func testCorrectionBudgetIsBoundedPerArtifact() {
        let tools = [ToolDefinition.shellRun]
        XCTAssertNotNil(AgentArtifactContractAuditGate.correction(
            path: "outputs/report.html",
            tools: tools,
            correctionCount: AgentArtifactContractAuditGate.correctionLimitPerPath - 1
        ))
        XCTAssertNil(AgentArtifactContractAuditGate.correction(
            path: "outputs/report.html",
            tools: tools,
            correctionCount: AgentArtifactContractAuditGate.correctionLimitPerPath
        ))
    }

    func testCorrectionRequiresSourceTableAndParserIntegrity() throws {
        let correction = try XCTUnwrap(AgentArtifactContractAuditGate.correction(
            path: "outputs/report.md",
            tools: [.shellRun],
            correctionCount: 0
        ))

        XCTAssertTrue(correction.prompt.contains("align every value with its exact source header"))
        XCTAssertTrue(correction.prompt.contains("Never relabel a half-period"))
        XCTAssertTrue(correction.prompt.contains("HALF1, HALF2, H1, and H2 columns are never annual values"))
        XCTAssertTrue(correction.prompt.contains("underlying observations independently"))
        XCTAssertTrue(correction.prompt.contains("locate intended table fields by their headers"))
        XCTAssertTrue(correction.prompt.contains("rightmost non-missing eligible period"))
        XCTAssertTrue(correction.prompt.contains("selected period label and value"))
        XCTAssertTrue(correction.prompt.contains("expected values copied from the artifact"))
    }

    func testRunnerRequiresAuditAndReauditsAfterRewrite() async throws {
        let root = try makeWorkspace()
        let firstWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.html",
                "content": "<table><tr><td>Atlas</td></tr></table>",
            ])
        )
        let validator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert open('outputs/report.html').read().count('<tr>') == 4\"",
            ])
        )
        let secondWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.html",
                "content": "<table><tr><td>Atlas</td></tr><tr><td>Asana</td></tr>"
                    + "<tr><td>monday.com</td></tr><tr><td>GitLab</td></tr></table>",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(firstWrite),
                .say("The report is complete."),
                .tool(validator),
                .tool(secondWrite),
                .say("The corrected report is complete."),
                .tool(validator),
                .say("The audited report is complete."),
                .say("The audited report is complete and verified."),
            ]),
            safety: AlwaysApprovingSafetyReviewer(),
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                return ToolResult(ok: true, stdout: "PASS: artifact contract\n")
            },
            maxToolSteps: 10
        )

        let result = try await runner.send(
            """
            Save the deliverable to outputs/report.html. Its table must contain exactly four \
            company rows, and the first five cells in every company row must be company and four \
            raw numeric values. Before finishing, verify the saved deliverable.
            """,
            in: ChatThread(title: "contract audit"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 5, "two writes need two audits and a final readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(
            result.thread.events.filter {
                $0.kind == .notice && $0.summary.contains("deterministic contract audit")
            }.count,
            2
        )
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "The audited report is complete and verified."
        )
    }

    func testRunnerStopsHonestlyAfterRepeatedlyIgnoredAuditCorrections() async throws {
        let root = try makeWorkspace()
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.html",
                "content": "<table><tr><td>Atlas</td></tr></table>",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(write),
                .say("Done."),
                .say("Done."),
                .say("Done."),
                .say("Done."),
            ]),
            safety: AlwaysApprovingSafetyReviewer(),
            maxToolSteps: 10
        )

        let result = try await runner.send(
            "Save outputs/report.html with exactly four company rows and verify it before finishing.",
            in: ChatThread(title: "bounded contract audit"),
            workspaceRoot: root
        )

        guard case .flailDetected(let reason) = result.stopReason else {
            return XCTFail("expected bounded audit stop, got \(result.stopReason)")
        }
        XCTAssertTrue(reason.contains("outputs/report.html"))
        XCTAssertTrue(reason.contains("deterministic contract audit"))
        XCTAssertEqual(
            result.thread.events.filter {
                $0.kind == .notice && $0.summary.contains("required a deterministic contract audit")
            }.count,
            AgentArtifactContractAuditGate.correctionLimitPerPath
        )
        XCTAssertEqual(result.toolResults.count, 1)
    }
}
