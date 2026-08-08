import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentSourceGroundingGateTests: XCTestCase {
    func testTabularGateFindsWrongCountsCategoriesAndMissingSliceRows() throws {
        let source = """
         1\tid,segment,competitor,objection,outcome
         2\tD01,Series A,none,none,won
         3\tD02,Series A,CloseFlow,SSO,lost
         4\tD03,Series A,CloseFlow,migration,won
         5\tD04,Series A,none,no urgency,lost
        """
        let artifact = """
        | Competitor | Won | Lost | Total | IDs |
        |---|---:|---:|---:|---|
        | CloseFlow | 0 | 1 | 1 | D02 |
        | none (our process) | 1 | 2 | 2 | D01, D04 |

        | Objection | Occurrences | Won | Lost | IDs |
        |---|---:|---:|---:|---|
        | none | 2 | 2 | 0 | D01, D03 |
        """

        let issues = AgentTabularSourceGroundingGate.issues(
            content: artifact,
            path: "outputs/review.md",
            sourceReadsByPath: ["inputs/deals.csv": source]
        )

        XCTAssertTrue(issues.contains { $0.contains("declares Lost=2") && $0.contains("support 1") })
        XCTAssertTrue(issues.contains { $0.contains("D03=migration") })
        XCTAssertTrue(issues.contains {
            $0.contains("matching competitor=closeflow") && $0.contains("[D02, D03]")
        })

        let correction = try XCTUnwrap(AgentTabularSourceGroundingGate.correction(
            userMessage: "Create outputs/review.md. Use only facts in the supplied sources.",
            issuesByPath: ["outputs/review.md": issues],
            auditCounts: [:]
        ))
        XCTAssertTrue(correction.prompt.contains("D03=migration"))
        XCTAssertTrue(correction.prompt.contains("every prose conclusion"))
        XCTAssertNil(AgentTabularSourceGroundingGate.correction(
            userMessage: "Create outputs/review.md. Use only facts in the supplied sources.",
            issuesByPath: ["outputs/review.md": issues],
            auditCounts: ["outputs/review.md": 2]
        ))
    }

    func testTabularGateAcceptsReconciledRowsAndQuotedCSV() throws {
        let source = """
        1\tid,segment,competitor,objection,outcome,note
        2\tD01,Series A,none,none,won,"CFO, Controller"
        3\tD02,Series A,CloseFlow,SSO,lost,"Security ""owner"" absent"
        4\tD03,Series A,CloseFlow,migration,won,Imported
        5\tD04,Series A,none,no urgency,lost,No trigger
        """
        let artifact = """
        | Competitor | Won | Lost | Total | IDs |
        |---|---:|---:|---:|---|
        | CloseFlow | 1 | 1 | 2 | D02, D03 |
        | none | 1 | 1 | 2 | D01, D04 |

        | Objection | Occurrences | Won | Lost | IDs |
        |---|---:|---:|---:|---|
        | none | 1 | 1 | 0 | D01 |
        | SSO | 1 | 0 | 1 | D02 |
        | migration | 1 | 1 | 0 | D03 |
        | no urgency | 1 | 0 | 1 | D04 |
        """

        let table = try XCTUnwrap(AgentTabularSourceGroundingGate.parseSourceTable(
            path: "inputs/deals.csv",
            renderedText: source
        ))
        XCTAssertEqual(table.recordsByID["D01"]?["note"], "CFO, Controller")
        XCTAssertEqual(table.recordsByID["D02"]?["note"], "Security \"owner\" absent")
        XCTAssertNotNil(AgentTabularSourceGroundingGate.parseSourceTable(
            path: "inputs/deals.csv",
            renderedText: source.replacingOccurrences(
                of: #"(?m)^\d+\t"#,
                with: "",
                options: .regularExpression
            )
        ))
        XCTAssertNil(AgentTabularSourceGroundingGate.parseSourceTable(
            path: "inputs/deals.csv",
            renderedText: source + "\n[showing lines 1-5 of 3000; pass offset=6 to read more]"
        ))
        XCTAssertEqual(
            AgentTabularSourceGroundingGate.issues(
                content: artifact,
                path: "outputs/review.md",
                sourceReadsByPath: ["inputs/deals.csv": source]
            ),
            []
        )
    }

    func testTabularGateFindsCase230WinLossReconciliationDefects() {
        let source = """
        1\tid,segment,source,competitor,objection,cycle_days,outcome,founder_action
        2\tD01,Series A,referral,none,none,24,won,quantified chasing time
        3\tD02,Series A,outbound,CloseFlow,SSO,41,lost,disclosed roadmap too late
        4\tD03,Growth,partner,MonthEnd Pro,ERP integration,58,lost,demoed before discovery
        5\tD04,Series A,outbound,none,price before value,19,lost,sent pricing first
        6\tD05,Series A,referral,CloseFlow,migration,33,won,ran sample import
        7\tD06,Growth,inbound,none,no urgency,47,lost,failed to confirm trigger
        8\tD07,Series A,inbound,none,none,21,won,involved CFO
        9\tD08,Series A,outbound,MonthEnd Pro,SSO,52,lost,no security owner
        10\tD09,Growth,referral,CloseFlow,price before value,36,lost,skipped workflow validation
        11\tD10,Series A,partner,none,migration,28,won,ran sample import
        12\tD11,Growth,inbound,none,no sponsor,63,lost,single-threaded Controller
        13\tD12,Series A,referral,CloseFlow,none,26,won,used Northstar proof
        """
        let artifact = """
        | Segment | Source | Won | Lost | Total | IDs |
        |---|---|---:|---:|---:|---|
        | Series A | outbound | 0 | 2 | 2 | D02, D08 |

        | Competitor | Lost | IDs |
        |---|---:|---|
        | CloseFlow | 3 | D02, D09 |
        | none | 2 | D04, D06, D11 |

        | Objection | Occurrences | Won | Lost | IDs |
        |---|---:|---:|---:|---|
        | none | 4 | 4 | 0 | D01, D05, D07, D10 |
        """

        let issues = AgentTabularSourceGroundingGate.issues(
            content: artifact,
            path: "outputs/wave5-230.md",
            sourceReadsByPath: ["inputs/data.csv": source]
        )

        XCTAssertTrue(issues.contains {
            $0.contains("matching segment=series a, source=outbound")
                && $0.contains("[D02, D04, D08]")
        })
        XCTAssertTrue(issues.contains {
            $0.contains("CloseFlow") && $0.contains("declares Lost=3") && $0.contains("support 2")
        })
        XCTAssertTrue(issues.contains {
            $0.contains("none") && $0.contains("declares Lost=2") && $0.contains("support 3")
        })
        XCTAssertTrue(issues.contains { $0.contains("D05=migration") && $0.contains("D10=migration") })
        XCTAssertTrue(issues.contains {
            $0.contains("matching objection=none") && $0.contains("[D01, D07, D12]")
        })
    }

    func testTabularGateFindsCase230IDBackedProseDefects() {
        let source = """
        1\tid,segment,source,competitor,objection,outcome
        2\tD01,Series A,referral,none,none,won
        3\tD02,Series A,outbound,CloseFlow,SSO,lost
        4\tD03,Growth,partner,MonthEnd Pro,ERP integration,lost
        5\tD04,Series A,outbound,none,price before value,lost
        6\tD05,Series A,referral,CloseFlow,migration,won
        7\tD06,Growth,inbound,none,no urgency,lost
        8\tD07,Series A,inbound,none,none,won
        9\tD08,Series A,outbound,MonthEnd Pro,SSO,lost
        10\tD09,Growth,referral,CloseFlow,price before value,lost
        11\tD10,Series A,partner,none,migration,won
        12\tD11,Growth,inbound,none,no sponsor,lost
        13\tD12,Series A,referral,CloseFlow,none,won
        """
        let artifact = """
        ### Source
        - Referral: 4 records (D01, D05, D12 won; D09 lost) - 3W/1L.
        - Outbound: 4 records (D02, D04, D08 lost; D05 won) - 1W/3L.

        ### Competitor
        - CloseFlow: 5 records (D05, D12 won; D02, D09 lost) - 2W/3L.

        ### Objection
        - none: 5 records (D01, D07, D10, D12 won; D04 lost) - 4W/1L.
        """

        let issues = AgentTabularSourceGroundingGate.issues(
            content: artifact,
            path: "outputs/wave5-230.md",
            sourceReadsByPath: ["inputs/data.csv": source]
        )

        XCTAssertTrue(issues.contains { $0.contains("Outbound") && $0.contains("D05=referral") })
        XCTAssertTrue(issues.contains {
            $0.contains("Outbound") && $0.contains("[D02, D04, D08]")
        })
        XCTAssertTrue(issues.contains {
            $0.contains("CloseFlow") && $0.contains("declares 5 records")
        })
        XCTAssertTrue(issues.contains {
            $0.contains("CloseFlow") && $0.contains("2W/3L") && $0.contains("2W/2L")
        })
        XCTAssertTrue(issues.contains { $0.contains("none") && $0.contains("D10=migration") })
        XCTAssertTrue(issues.contains { $0.contains("none") && $0.contains("[D01, D07, D12]") })
    }

    func testTabularGateAcceptsReconciledIDBackedProse() {
        let source = """
        1\tid,source,competitor,outcome
        2\tD01,referral,none,won
        3\tD02,outbound,CloseFlow,lost
        4\tD03,outbound,CloseFlow,won
        """
        let artifact = """
        ### Source
        - Referral: 1 record (D01 won) - 1W/0L.
        - Outbound: 2 records (D02 lost; D03 won) - 1W/1L.

        ### Competitor
        - CloseFlow: 2 records (D02 lost; D03 won) - 1W/1L.
        - none: 1 record (D01 won) - 1W/0L.
        """

        XCTAssertEqual(
            AgentTabularSourceGroundingGate.issues(
                content: artifact,
                path: "outputs/review.md",
                sourceReadsByPath: ["inputs/data.csv": source]
            ),
            []
        )
    }

    func testRunnerReconcilesTabularSourceRowsBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("inputs/deals.csv")
        try FileManager.default.createDirectory(
            at: input.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        id,segment,competitor,outcome
        D01,Series A,none,won
        D02,Series A,CloseFlow,lost
        D03,Series A,CloseFlow,won
        """.write(to: input, atomically: true, encoding: .utf8)

        let incorrect = """
        | Competitor | Won | Lost | Total | IDs |
        |---|---:|---:|---:|---|
        | CloseFlow | 0 | 1 | 1 | D02 |
        """
        let corrected = """
        | Competitor | Won | Lost | Total | IDs |
        |---|---:|---:|---:|---|
        | CloseFlow | 1 | 1 | 2 | D02, D03 |
        """
        let outputRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/review.md"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(ToolCall(
                    name: ToolDefinition.fileRead.name,
                    argumentsJSON: ToolArguments.json(["path": "inputs/deals.csv"])
                )),
                .tool(writeCall(path: "outputs/review.md", content: incorrect)),
                .say("The review is complete."),
                .tool(writeCall(path: "outputs/review.md", content: corrected)),
                .say("The review is corrected."),
                .tool(outputRead),
                .say("The corrected review is complete and verified."),
            ]),
            maxToolSteps: 10
        )

        let result = try await runner.send(
            "Read inputs/deals.csv and create outputs/review.md. "
                + "Use only facts in the supplied sources. "
                + "After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("tabular source reconciliation")
        })
        XCTAssertEqual(
            try String(
                contentsOf: root.appendingPathComponent("outputs/review.md"),
                encoding: .utf8
            ),
            corrected
        )
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "The corrected review is complete and verified."
        )
    }

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

    private func writeCall(path: String = "outputs/brief.md", content: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": path,
                "content": content,
            ])
        )
    }
}
