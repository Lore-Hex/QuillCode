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
        let stillUnsupported = "# Outreach\n\nWe are not selling. Join a 30-minute call.\n"
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(writeCall(content: unsupported)),
                .say("Created and verified outputs/brief.md."),
                .tool(writeCall(content: partiallyCorrected)),
                .say("Created outputs/brief.md."),
                .tool(writeCall(content: stillUnsupported)),
                .say("Created outputs/brief.md."),
                .tool(writeCall(content: "# Outreach\n\nNo pitch. Join a 30-minute call.\n")),
            ]),
            maxToolSteps: 10
        )

        let result = try await runner.send(
            "Create outputs/brief.md. Use only facts in the supplied sources. "
                + "After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(
            result.toolResults.count,
            5,
            "three model writes, one deterministic repair, and the forced final readback"
        )
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("source-grounding audit")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("removed unsupported sensitive claims")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/brief.md"), encoding: .utf8),
            "# Outreach\n\n"
        )
    }

    func testFormattingOnlyAuditSkipsVerificationAndFinalizesDeterministicRepair() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let unsupported = "# Outreach\n\nThis is a paid 30-minute call and not a sales pitch.\n"
        let formattingOnlyRewrite = unsupported.trimmingCharacters(in: .newlines)
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(writeCall(content: unsupported)),
                .say("Created outputs/brief.md."),
                .tool(writeCall(content: formattingOnlyRewrite)),
                .say("Created outputs/brief.md."),
                .tool(writeCall(content: "# Outreach\n\nNo pitch.\n")),
            ]),
            maxToolSteps: 8
        )

        let result = try await runner.send(
            "Create outputs/brief.md. Use only facts in the supplied sources. "
                + "After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(
            result.toolResults.count,
            4,
            "two model writes, one deterministic repair, and the forced final readback"
        )
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/brief.md"), encoding: .utf8),
            "# Outreach\n"
        )
    }

    func testAuditContentComparisonIgnoresOnlyOuterAndTrailingWhitespace() {
        XCTAssertFalse(AgentSourceGroundingGate.isMateriallyDifferent(
            "\n# Brief  \n\nBody\t\n",
            "# Brief\n\nBody"
        ))
        XCTAssertTrue(AgentSourceGroundingGate.isMateriallyDifferent(
            "# Brief\n\nBody",
            "# Brief\n\nChanged body"
        ))
    }

    func testSensitiveClaimBoundaryPreservesGroundedAndUnknownStatements() throws {
        let source = "The interview lasts 30 minutes. This is not a sales call."
        let artifact = """
        # Outreach
        The interview lasts 30 minutes.
        This is not a sales call.
        We can work around your schedule.
        Compensation is unknown.
        Meet us within the next 2 weeks.
        `Example: a paid interview`
        """

        XCTAssertTrue(AgentSourceGroundingGate.containsUnsupportedSensitiveClaim(
            content: artifact,
            path: "outputs/brief.md",
            sourceText: source
        ))
        let repaired = try XCTUnwrap(AgentSourceGroundingGate.removingUnsupportedSensitiveClaims(
            content: artifact,
            path: "outputs/brief.md",
            sourceText: source
        ))
        XCTAssertTrue(repaired.contains("The interview lasts 30 minutes."))
        XCTAssertTrue(repaired.contains("This is not a sales call."))
        XCTAssertTrue(repaired.contains("Compensation is unknown."))
        XCTAssertTrue(repaired.contains("`Example: a paid interview`"))
        XCTAssertFalse(repaired.contains("work around"))
        XCTAssertFalse(repaired.contains("next 2 weeks"))
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
