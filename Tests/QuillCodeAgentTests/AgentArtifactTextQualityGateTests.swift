import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentArtifactTextQualityGateTests: XCTestCase {
    func testDetectsVisibleEscapesButIgnoresCodeExamples() {
        XCTAssertTrue(AgentArtifactTextQualityGate.containsMalformedLiteralEscape(
            content: "# Report\n\nLoop health:\\n- Activation is stable.\n",
            path: "outputs/report.md"
        ))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsMalformedLiteralEscape(
            content: """
            # API

            Use `\\n` for a newline.

            ```swift
            let value = "\\n"
            ```
            """,
            path: "outputs/report.md"
        ))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsMalformedLiteralEscape(
            content: "# Report\n\nLoop health:\n- Activation is stable.\n",
            path: "outputs/report.md"
        ))
    }

    func testDeterministicEscapeRepairPreservesInlineAndFencedCode() throws {
        let content = #"""
        # Report\n\n## Plan\n- Interview five founders.\n- Ship one workflow.

        Use `\n` to document a newline.

        ```text
        first\nsecond
        ```
        """#

        let repaired = try XCTUnwrap(AgentArtifactTextQualityGate.replacingMalformedLiteralEscapes(
            content: content,
            path: "outputs/report.md"
        ))

        XCTAssertTrue(repaired.contains("# Report\n\n## Plan\n- Interview five founders.\n- Ship one workflow."))
        XCTAssertTrue(repaired.contains("Use `\\n` to document a newline."))
        XCTAssertTrue(repaired.contains("```text\nfirst\\nsecond\n```"))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsMalformedLiteralEscape(
            content: repaired,
            path: "outputs/report.md"
        ))
    }

    func testDetectsBracketedAndBracedFieldsButIgnoresMarkdownControlsAndCitations() {
        XCTAssertTrue(AgentArtifactTextQualityGate.containsBracketedPlaceholder(
            content: "Ask what their role is at {Company}, then repeat [their words].",
            path: "outputs/guide.md"
        ))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsBracketedPlaceholder(
            content: "- [ ] Pending\n- [x] Complete\nSee [source](https://example.test), [1], and [^note].",
            path: "outputs/guide.md"
        ))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsBracketedPlaceholder(
            content: "Use `[company]` only as a documented example.\n```text\n[name]\n```",
            path: "outputs/guide.md"
        ))
    }

    func testPlaceholderCorrectionRequiresExplicitPlaceholderFreeRequest() throws {
        let paths: Set<String> = ["outputs/guide.md"]
        XCTAssertNil(AgentArtifactTextQualityGate.placeholderCorrection(
            userMessage: "Create a reusable template at outputs/guide.md.",
            placeholderPaths: paths
        ))
        let correction = try XCTUnwrap(AgentArtifactTextQualityGate.placeholderCorrection(
            userMessage: "Create outputs/guide.md. Do not leave bracketed fill-in fields.",
            placeholderPaths: paths
        ))
        XCTAssertEqual(correction.path, "outputs/guide.md")
        XCTAssertTrue(correction.prompt.contains("blank lines, empty cells, or checkboxes"))

        let evaluationCorrection = try XCTUnwrap(AgentArtifactTextQualityGate.placeholderCorrection(
            userMessage: "Create outputs/guide.md. Do not leave template placeholders or blank fields.",
            placeholderPaths: paths
        ))
        XCTAssertEqual(evaluationCorrection.path, "outputs/guide.md")
        XCTAssertTrue(evaluationCorrection.prompt.contains("Fully personalize repeated messages"))
    }

    func testDeterministicPlaceholderRepairPreservesMarkdownControlsAndCode() throws {
        let content = """
        Hi {First name}, schedule at [calendar link] for {Company}.
        - [ ] Pending
        - [x] Complete
        See [source](https://example.test), [1], and [^note].
        Use `[company]` as a documented example.
        ```text
        [name]
        ```
        """

        let repaired = try XCTUnwrap(AgentArtifactTextQualityGate.replacingBracketedPlaceholders(
            content: content,
            path: "outputs/outreach.md"
        ))

        XCTAssertTrue(repaired.contains("Hi ________, schedule at ________ for ________."))
        XCTAssertTrue(repaired.contains("- [ ] Pending\n- [x] Complete"))
        XCTAssertTrue(repaired.contains("[source](https://example.test), [1], and [^note]"))
        XCTAssertTrue(repaired.contains("`[company]`"))
        XCTAssertTrue(repaired.contains("```text\n[name]\n```"))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsBracketedPlaceholder(
            content: repaired,
            path: "outputs/outreach.md"
        ))
    }

    func testDetectsContradictoryEnumeratedCountsButIgnoresExamplesAndProseLists() {
        XCTAssertTrue(AgentArtifactTextQualityGate.containsContradictoryEnumeratedCount(
            content: "Series A Controllers: 6 records (I-01, I-03, I-05, I-07, I-09, I-11, I-13, I-15, I-17)",
            path: "outputs/report.md"
        ))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsContradictoryEnumeratedCount(
            content: "Nine records (I-01, I-03, I-05) are examples, including Maya, Lee, and Jo.",
            path: "outputs/report.md"
        ))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsContradictoryEnumeratedCount(
            content: "Use `6 records (I-01, I-03, I-05)` as a malformed example.\n```text\n6 records (I-01, I-03)\n```",
            path: "outputs/report.md"
        ))
    }

    func testDeterministicEnumeratedCountRepairChangesOnlyVisibleContradictoryNumeral() throws {
        let content = """
        Series A Controllers: 6 records (I-01, I-03, I-05, I-07, I-09, I-11, I-13, I-15, I-17)
        Keep `6 records (I-01, I-03, I-05)` as an example.
        ```text
        4 records (A-01, A-02)
        ```
        """

        let repaired = try XCTUnwrap(
            AgentArtifactTextQualityGate.replacingContradictoryEnumeratedCounts(
                content: content,
                path: "outputs/report.md"
            )
        )

        XCTAssertTrue(repaired.contains("9 records (I-01, I-03, I-05, I-07, I-09, I-11, I-13, I-15, I-17)"))
        XCTAssertTrue(repaired.contains("`6 records (I-01, I-03, I-05)`"))
        XCTAssertTrue(repaired.contains("```text\n4 records (A-01, A-02)\n```"))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsContradictoryEnumeratedCount(
            content: repaired,
            path: "outputs/report.md"
        ))
    }

    func testDetectsEmptyMarkdownSectionsWithoutTreatingNestedContentOrCodeAsEmpty() {
        let content = """
        # Report

        ## Populated parent
        ### Detail
        Evidence lives here.

        ## Code
        ```text
        # This is code, not a section
        value
        ```

        ## Empty middle
        ## Final
        """

        XCTAssertEqual(
            AgentArtifactTextQualityGate.emptyMarkdownSectionTitles(
                content: content,
                path: "outputs/report.md"
            ),
            ["Empty middle", "Final"]
        )
        XCTAssertTrue(AgentArtifactTextQualityGate.emptyMarkdownSectionTitles(
            content: "# Not Markdown",
            path: "outputs/report.txt"
        ).isEmpty)
    }

    func testDeterministicMarkdownCompletenessRepairRemovesOnlyEmptyHeadings() throws {
        let content = """
        # Report

        ## Evidence
        The result is grounded.

        ## Empty

        ## Code
        ```text
        # Keep this line
        ```

        ## Trailing
        """

        let repaired = try XCTUnwrap(
            AgentArtifactTextQualityGate.removingEmptyMarkdownSections(
                content: content,
                path: "outputs/report.md"
            )
        )

        XCTAssertTrue(repaired.contains("## Evidence\nThe result is grounded."))
        XCTAssertTrue(repaired.contains("```text\n# Keep this line\n```"))
        XCTAssertFalse(repaired.contains("## Empty"))
        XCTAssertFalse(repaired.contains("## Trailing"))
        XCTAssertTrue(AgentArtifactTextQualityGate.emptyMarkdownSectionTitles(
            content: repaired,
            path: "outputs/report.md"
        ).isEmpty)
    }

    func testMalformedNamedArtifactIsRewrittenBeforeReadbackAndCompletion() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let malformed = "# Report\n\nLoop health:\\n- Activation is stable.\n"
        let corrected = "# Report\n\nLoop health:\n- Activation is stable.\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: malformed)),
            .say("Created and verified outputs/report.md."),
            .tool(writeCall(content: corrected)),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]))

        let result = try await runner.send(
            "Create outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 3, "two writes and the forced final readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("clean text formatting")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    func testMalformedArtifactIsDeterministicallyRepairedAfterIgnoredRewrite() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let malformed = "# Report\\n\\n## Plan\\n- Interview five founders.\\n- Ship one workflow.\n"
        let corrected = "# Report\n\n## Plan\n- Interview five founders.\n- Ship one workflow.\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: malformed)),
            .tool(readCall()),
            .say("Created and verified outputs/report.md."),
            .say("Created and verified outputs/report.md."),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]), maxToolSteps: 8)

        let result = try await runner.send(
            "Create outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 4, "two writes and two readbacks")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("clean text formatting")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("decoded literal formatting escapes")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    func testPlaceholderFreeNamedArtifactIsRewrittenBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let incomplete = "# Guide\n\nHi {First name}, what is your role at {Company}?\n"
        let corrected = "# Guide\n\nWhat is your role, and what work do you own?\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: incomplete)),
            .say("Created and verified outputs/report.md."),
            .tool(writeCall(content: corrected)),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]))

        let result = try await runner.send(
            "Create outputs/report.md. Do not leave template placeholders or blank fields. "
                + "After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 3, "two writes and the forced final readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("placeholder-free text")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    func testPlaceholderFreeArtifactIsRewrittenAfterPrematureReadback() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let incomplete = "# Outreach\n\nHi [First name], book here: [calendar link].\n"
        let corrected = "# Outreach\n\nHi ________, book here: ________.\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: incomplete)),
            .tool(readCall()),
            .say("Created and verified outputs/report.md."),
            .say("Created and verified outputs/report.md."),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]), maxToolSteps: 8)

        let result = try await runner.send(
            "Create outputs/report.md. Do not leave bracketed fill-in fields. "
                + "After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 4, "two writes and two readbacks")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("placeholder-free text")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("fill-in fields with blanks")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    func testContradictoryEnumeratedCountIsRewrittenBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let contradictory = "# Report\n\n6 records (I-01, I-03, I-05, I-07, I-09, I-11, I-13, I-15, I-17)\n"
        let corrected = "# Report\n\n9 records (I-01, I-03, I-05, I-07, I-09, I-11, I-13, I-15, I-17)\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: contradictory)),
            .say("Created and verified outputs/report.md."),
            .tool(writeCall(content: corrected)),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]))

        let result = try await runner.send(
            "Create outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 3, "two writes and the forced final readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("consistent enumerated counts")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    func testContradictoryEnumeratedCountIsDeterministicallyRepairedAfterIgnoredRewrite() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let contradictory = "# Report\n\n2 records (I-01, I-03, I-05)\n"
        let corrected = "# Report\n\n3 records (I-01, I-03, I-05)\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: contradictory)),
            .tool(readCall()),
            .say("Created and verified outputs/report.md."),
            .say("Created and verified outputs/report.md."),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]), maxToolSteps: 8)

        let result = try await runner.send(
            "Create outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 4, "two writes and two readbacks")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("consistent enumerated counts")
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("reconciled an enumerated record count")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    func testIncompleteMarkdownArtifactIsRewrittenBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let incomplete = "# Report\n\n## Evidence\nGrounded result.\n\n## Notes\n"
        let corrected = "# Report\n\n## Evidence\nGrounded result.\n\n## Notes\nNo additional caveats.\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: incomplete)),
            .say("Created and verified outputs/report.md."),
            .tool(writeCall(content: corrected)),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]))

        let result = try await runner.send(
            "Create outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 3, "two writes and the forced final readback")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("complete Markdown sections")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    func testIncompleteMarkdownArtifactIsDeterministicallyRepairedAfterIgnoredRewrite() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let incomplete = "# Report\n\n## Evidence\nGrounded result.\n\n## Notes\n"
        let corrected = "# Report\n\n## Evidence\nGrounded result.\n\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: incomplete)),
            .tool(readCall()),
            .say("Created and verified outputs/report.md."),
            .say("Created and verified outputs/report.md."),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]), maxToolSteps: 8)

        let result = try await runner.send(
            "Create outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 4, "two writes and two readbacks")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("removed empty Markdown headings")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    private func writeCall(content: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": content,
            ])
        )
    }

    private func readCall() -> ToolCall {
        ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
        )
    }
}
