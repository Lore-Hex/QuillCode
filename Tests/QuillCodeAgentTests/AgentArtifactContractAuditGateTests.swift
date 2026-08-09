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
}
