import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentSourceGroundingGateTests: XCTestCase {
    func testCorrectionRequiresExplicitSourceOnlyConstraintAndNamedWrittenArtifact() throws {
        let written: Set<String> = ["outputs/brief.md"]
        XCTAssertNil(AgentSourceGroundingGate.correction(
            userMessage: "Create outputs/brief.md from the supplied sources.",
            writtenPaths: written,
            auditCounts: [:],
            verificationPaths: []
        ))
        XCTAssertNil(AgentSourceGroundingGate.correction(
            userMessage: "Use only facts in the supplied sources.",
            writtenPaths: written,
            auditCounts: [:],
            verificationPaths: []
        ))

        let correction = try XCTUnwrap(AgentSourceGroundingGate.correction(
            userMessage: "Create outputs/brief.md. Use only facts in those supplied sources.",
            writtenPaths: written,
            auditCounts: [:],
            verificationPaths: []
        ))
        XCTAssertEqual(correction.path, "outputs/brief.md")
        XCTAssertTrue(correction.prompt.contains("invented payment or compensation"))
        XCTAssertTrue(correction.prompt.contains("Return exactly one tool action now"))

        XCTAssertNil(AgentSourceGroundingGate.correction(
            userMessage: "Create outputs/brief.md. Use only facts in those supplied sources.",
            writtenPaths: written,
            auditCounts: ["outputs/brief.md": 1],
            verificationPaths: []
        ))

        let verification = try XCTUnwrap(AgentSourceGroundingGate.correction(
            userMessage: "Create outputs/brief.md. Use only facts in those supplied sources.",
            writtenPaths: written,
            auditCounts: ["outputs/brief.md": 1],
            verificationPaths: written
        ))
        XCTAssertTrue(verification.prompt.contains("verification pass"))
        XCTAssertTrue(verification.prompt.contains("subject lines"))
        XCTAssertNil(AgentSourceGroundingGate.correction(
            userMessage: "Create outputs/brief.md. Use only facts in those supplied sources.",
            writtenPaths: written,
            auditCounts: ["outputs/brief.md": 2],
            verificationPaths: written
        ))
    }

    func testSourceOnlyArtifactIsAuditedAndRewrittenBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let unsupported = "# Outreach\n\nThis is a paid 30-minute call and not a sales pitch.\n"
        let partiallyCorrected = "# Outreach\n\nJoin a 30-minute research conversation.\n"
        let corrected = "# Outreach\n\nShare your experience with us.\n"
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(writeCall(content: unsupported)),
                .say("Created and verified outputs/brief.md."),
                .tool(writeCall(content: partiallyCorrected)),
                .say("Created outputs/brief.md."),
                .tool(writeCall(content: corrected)),
                .say("Created outputs/brief.md."),
                .say("Created and verified outputs/brief.md."),
            ]),
            maxToolSteps: 8
        )

        let result = try await runner.send(
            "Create outputs/brief.md. Use only facts in the supplied sources. "
                + "After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 4, "three writes and the forced final readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("source-grounding audit")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/brief.md"), encoding: .utf8),
            corrected
        )
    }

    private func writeCall(content: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/brief.md",
                "content": content,
            ])
        )
    }
}
