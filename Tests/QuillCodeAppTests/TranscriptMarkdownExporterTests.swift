import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class TranscriptMarkdownExporterTests: XCTestCase {
    private func card(
        id: String, title: String, subtitle: String = "",
        input: String? = nil, output: String? = nil
    ) -> ToolCardState {
        ToolCardState(id: id, title: title, subtitle: subtitle, status: .done, inputJSON: input, outputJSON: output)
    }

    private func transcript(_ items: [TranscriptTimelineItemSurface]) -> TranscriptSurface {
        TranscriptSurface(messages: [], toolCards: [], timelineItems: items)
    }

    func testExportsInterleavedMessagesAndToolCardsInTimelineOrder() {
        let user = MessageSurface(message: ChatMessage(role: .user, content: "Run the tests"))
        let tool = card(id: "t1", title: "host.shell.run", input: #"{"command":"swift test"}"#, output: "All tests passed")
        let assistant = MessageSurface(message: ChatMessage(role: .assistant, content: "Done — all green."))

        let markdown = TranscriptMarkdownExporter.markdown(
            for: transcript([.message(user), .toolCard(tool), .message(assistant)])
        )

        XCTAssertEqual(markdown, """
        ## User

        Run the tests

        ### Shell command

        ```
        All tests passed
        ```

        ## Assistant

        Done — all green.
        """)
    }

    func testToolCardTextPrefersOutputThenInputThenTitleSubtitle() {
        XCTAssertTrue(TranscriptMarkdownExporter.markdown(
            for: transcript([.toolCard(card(id: "a", title: "T", input: "the-input", output: "the-output"))])
        ).contains("```\nthe-output\n```"))

        XCTAssertTrue(TranscriptMarkdownExporter.markdown(
            for: transcript([.toolCard(card(id: "b", title: "T", input: "the-input"))])
        ).contains("```\nthe-input\n```"))

        XCTAssertEqual(
            TranscriptMarkdownExporter.markdown(
                for: transcript([.toolCard(card(id: "c", title: "host.git.diff", subtitle: "no changes"))])
            ),
            "### Git diff\n\n```\nGit diff\nno changes\n```"
        )
    }

    func testSkipsEmptyMessageBodiesButKeepsHeadingsForRealOnes() {
        let blank = MessageSurface(message: ChatMessage(role: .user, content: "   "))
        let real = MessageSurface(message: ChatMessage(role: .assistant, content: "hi"))
        XCTAssertEqual(
            TranscriptMarkdownExporter.markdown(for: transcript([.message(blank), .message(real)])),
            "## Assistant\n\nhi"
        )
    }

    func testEmptyTranscriptProducesEmptyString() {
        XCTAssertEqual(TranscriptMarkdownExporter.markdown(for: transcript([])), "")
    }

    func testTrimsAtTheTextBoundaryMatchingTheSharedFormatter() {
        // Whitespace-only output is skipped (falls through to the trimmed title/subtitle),
        // and the subtitle is trimmed — the exact boundary the Swift↔JS parity contract guards.
        let tool = card(id: "t1", title: "host.shell.run", subtitle: "  done  ", input: nil, output: "   ")
        XCTAssertEqual(
            TranscriptMarkdownExporter.markdown(for: transcript([.toolCard(tool)])),
            "### Shell command\n\n```\nShell command\ndone\n```"
        )
    }

    func testUsesALongerFenceWhenOutputContainsTripleBacktick() {
        let tool = card(id: "t1", title: "host.shell.run", output: "```\ncode\n```")
        XCTAssertEqual(
            TranscriptMarkdownExporter.markdown(for: transcript([.toolCard(tool)])),
            "### Shell command\n\n````\n```\ncode\n```\n````"
        )
    }

    func testSkipsSystemAndToolMessageHeadings() {
        let system = MessageSurface(message: ChatMessage(role: .system, content: "secret system prompt"))
        let tool = MessageSurface(message: ChatMessage(role: .tool, content: "tool noise"))
        let user = MessageSurface(message: ChatMessage(role: .user, content: "hi"))
        XCTAssertEqual(
            TranscriptMarkdownExporter.markdown(for: transcript([.message(system), .message(tool), .message(user)])),
            "## User\n\nhi"
        )
    }

    func testClipboardMarkdownIsNilWhenNothingCopyable() {
        XCTAssertNil(TranscriptMarkdownExporter.clipboardMarkdown(for: transcript([])))
        let blank = MessageSurface(message: ChatMessage(role: .user, content: "   "))
        XCTAssertNil(TranscriptMarkdownExporter.clipboardMarkdown(for: transcript([.message(blank)])))
        XCTAssertNil(TranscriptMarkdownExporter.exportableMarkdown(for: transcript([.message(blank)])))
        let real = MessageSurface(message: ChatMessage(role: .assistant, content: "answer"))
        XCTAssertEqual(
            TranscriptMarkdownExporter.clipboardMarkdown(for: transcript([.message(real)])),
            "## Assistant\n\nanswer"
        )
        XCTAssertEqual(
            TranscriptMarkdownExporter.exportableMarkdown(for: transcript([.message(real)])),
            "## Assistant\n\nanswer"
        )
    }

    func testMatchesTheHarnessParityFixtureByteForByte() {
        // The SAME fixture is asserted in core.spec.ts against window.__lastConversationMarkdown,
        // so Swift and the JS harness are pinned to identical clipboard bytes (parity contract).
        let user = MessageSurface(message: ChatMessage(role: .user, content: "Run the tests"))
        let tool = card(
            id: "t1", title: "host.shell.run",
            output: "{\n  \"ok\": true,\n  \"stdout\": \"ran: the tests\\n\",\n  \"stderr\": \"\",\n  \"exitCode\": 0\n}"
        )
        let assistant = MessageSurface(message: ChatMessage(role: .assistant, content: "Output:\nran: the tests"))

        let markdown = TranscriptMarkdownExporter.markdown(
            for: transcript([.message(user), .toolCard(tool), .message(assistant)])
        )

        XCTAssertEqual(markdown,
            "## User\n\nRun the tests\n\n"
            + "### Shell command\n\n```\n"
            + "{\n  \"ok\": true,\n  \"stdout\": \"ran: the tests\\n\",\n  \"stderr\": \"\",\n  \"exitCode\": 0\n}\n"
            + "```\n\n## Assistant\n\nOutput:\nran: the tests"
        )
    }

    func testFencedBlockReusesPerItemFormatterVerbatim() {
        // Locks "export == per-item copy": the fenced block contains exactly the shared
        // formatter's output, so the two copy paths can never silently diverge.
        let tool = card(id: "t1", title: "host.git.diff", input: "in", output: "diff-output")
        let perItem = TranscriptItemTextFormatter.text(for: tool)
        let markdown = TranscriptMarkdownExporter.markdown(for: transcript([.toolCard(tool)]))
        XCTAssertEqual(perItem, "diff-output")
        XCTAssertTrue(markdown.contains("```\n\(perItem)\n```"))
    }
}
