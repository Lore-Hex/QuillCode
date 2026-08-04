import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// F29 — citation-integrity enforcement. Live failures this closes: a speaker-brief run cited a
/// search-snippet URL it never fetched (fetch log shows a different path on the same host), and a
/// re-drive on a second model leaked an unfetched pointer link — both under an explicit prompt
/// rule forbidding it. Prompts are insufficient for this class; the run loop must audit the
/// terminal answer against the run's grounded provenance (fetched pages, their content, read
/// files, the user's request, prior turns) — search snippets stay ungrounded on purpose.
final class AgentCitationIntegrityGateTests: XCTestCase {
    // MARK: - Normalization

    func testNormalizeStripsFragmentAndTrailingSlashKeepsPortAndQuery() {
        XCTAssertEqual(
            AgentCitationIntegrityGate.normalize("HTTPS://Example.COM/Path/#section"),
            "https://example.com/Path"
        )
        XCTAssertEqual(
            AgentCitationIntegrityGate.normalize("https://example.com/"),
            "https://example.com"
        )
        XCTAssertEqual(
            AgentCitationIntegrityGate.normalize("https://example.com:8443/a?b=1"),
            "https://example.com:8443/a?b=1"
        )
    }

    func testFinalURLParsedFromFetchSummaryLine() {
        XCTAssertEqual(
            AgentCitationIntegrityGate.finalURL(
                fromFetchStdout: "Fetched https://www.notion.com/pricing (HTTP 200, text/html, 1.2 MB fetched, converted to markdown).\n\n# Pricing"
            ),
            "https://www.notion.com/pricing"
        )
        XCTAssertNil(AgentCitationIntegrityGate.finalURL(fromFetchStdout: "some other output"))
    }

    // MARK: - Citation extraction (the audited side)

    func testMarkdownLinksExtractedBareURLsIgnored() {
        let text = """
        See [the docs](https://example.com/docs) and also https://bare.example.com/ignored
        plus [another](http://second.example.org/page).
        """
        XCTAssertEqual(
            AgentCitationIntegrityGate.markdownLinkedURLs(in: text),
            ["https://example.com/docs", "http://second.example.org/page"]
        )
    }

    func testParenthesizedURLsExtractIntact() {
        // The Wikipedia shape that permanently false-positived under a lazy regex.
        XCTAssertEqual(
            AgentCitationIntegrityGate.markdownLinkedURLs(
                in: "[Swift](https://en.wikipedia.org/wiki/Swift_(programming_language)) is nice."
            ),
            ["https://en.wikipedia.org/wiki/Swift_(programming_language)"]
        )
    }

    func testTitledAndAngleBracketLinksExtract() {
        XCTAssertEqual(
            AgentCitationIntegrityGate.markdownLinkedURLs(
                in: #"[docs](https://example.com/docs "Docs title") and [x](<https://example.com/angle>)"#
            ),
            ["https://example.com/docs", "https://example.com/angle"]
        )
    }

    func testImageEmbedsAndCodeFencesAreNotCitations() {
        let text = """
        ![chart](https://example.com/chart.png)
        ```
        [example](https://example.com/in-code-fence)
        ```
        ~~~
        [tilde](https://example.com/in-tilde-fence)
        ~~~
        [real](https://example.com/real)
        """
        XCTAssertEqual(
            AgentCitationIntegrityGate.markdownLinkedURLs(in: text),
            ["https://example.com/real"]
        )
    }

    // MARK: - Provenance extraction (the allowing side)

    func testAllURLsHarvestsBareAndParenthesizedSpellings() {
        let text = """
        Fetched https://en.wikipedia.org/wiki/Swift_(programming_language) (HTTP 200).
        Body links: <a href="https://example.com/deep">deep</a>, trailing punctuation https://x.example.com/p.
        """
        let urls = AgentCitationIntegrityGate.allURLs(in: text)
        XCTAssertTrue(urls.contains("https://en.wikipedia.org/wiki/Swift_(programming_language)"))
        XCTAssertTrue(urls.contains("https://example.com/deep"))
        XCTAssertTrue(urls.contains("https://x.example.com/p"))
    }

    // MARK: - ungroundedCitations

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("citation-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testUngroundedLinkFlaggedGroundedOneIsNot() throws {
        let root = try makeWorkspace()
        let offenders = AgentCitationIntegrityGate.ungroundedCitations(
            sayText: "See [a](https://example.com/fetched/) and [b](https://example.com/guessed).",
            userMessage: "Research the site.",
            workspaceRoot: root,
            groundedURLs: [AgentCitationIntegrityGate.normalize("https://example.com/fetched")],
            writtenWorkspacePaths: []
        )
        XCTAssertEqual(offenders, ["https://example.com/guessed"])
    }

    func testLinkFoundInsideFetchedContentIsGrounded() throws {
        // The wizardzines case: jvns.ca was fetched and its content links wizardzines.com. Citing
        // that pointer is grounded provenance — the harvest side collects URLs from fetched output.
        let root = try makeWorkspace()
        let fetchedPage = "Fetched https://jvns.ca (HTTP 200).\n\nI make [Wizard Zines](https://wizardzines.com/)!"
        var grounded = Set<String>()
        for url in AgentCitationIntegrityGate.allURLs(in: fetchedPage) {
            grounded.insert(AgentCitationIntegrityGate.normalize(url))
        }
        let offenders = AgentCitationIntegrityGate.ungroundedCitations(
            sayText: "Creator of [Wizard Zines](https://wizardzines.com).",
            userMessage: "Build a speaker brief.",
            workspaceRoot: root,
            groundedURLs: grounded,
            writtenWorkspacePaths: []
        )
        XCTAssertTrue(offenders.isEmpty)
    }

    func testOnlyRunWrittenMarkdownDeliverablesAreScanned() throws {
        let root = try makeWorkspace()
        try """
        Creator of [Wizard Zines](https://wizardzines.com), fetched [site](https://jvns.ca/).
        """.write(to: root.appendingPathComponent("speaker-brief.md"), atomically: true, encoding: .utf8)
        try "[user link](https://user-supplied.example.com/page)"
            .write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let grounded: Set<String> = [AgentCitationIntegrityGate.normalize("https://jvns.ca/")]
        // notes.md exists and is named in the task, but the run never wrote it — user input files
        // are never audited. speaker-brief.md WAS written by the run and is audited.
        let offenders = AgentCitationIntegrityGate.ungroundedCitations(
            sayText: "Done.",
            userMessage: "Read notes.md, then build a brief and write speaker-brief.md",
            workspaceRoot: root,
            groundedURLs: grounded,
            writtenWorkspacePaths: ["speaker-brief.md"]
        )
        XCTAssertEqual(offenders, ["https://wizardzines.com"])
    }

    // MARK: - Run-loop provenance recording

    func testRunLoopHarvestsFetchAndReadOutputButNotSearch() {
        var state = AgentRunLoopState()
        let root = URL(fileURLWithPath: "/tmp")
        let signature: (URL) -> String = { _ in "" }
        func record(_ name: String, args: String, stdout: String, artifacts: [String] = []) {
            _ = state.recordCompletedStep(
                AgentToolStepCompletion(
                    call: ToolCall(name: name, argumentsJSON: args),
                    result: ToolResult(ok: true, stdout: stdout, artifacts: artifacts),
                    followUpReviewResult: nil,
                    toolResults: []
                ),
                workspaceRoot: root,
                stateSignature: signature
            )
        }
        record(
            "host.web.fetch",
            args: #"{"url":"https://www.notion.so/pricing"}"#,
            stdout: "Fetched https://www.notion.com/pricing (HTTP 200).\n\nBody [link](https://example.com/inside)"
        )
        record(
            "host.web.search",
            args: #"{"query":"swift"}"#,
            stdout: "1. https://snippet.example.com/unread — a search result"
        )
        record(
            "host.file.write",
            args: #"{"path":"brief.md","content":"x"}"#,
            stdout: "Wrote /tmp/brief.md",
            artifacts: ["/tmp/brief.md"]
        )

        XCTAssertTrue(state.didFetchSuccessfully)
        XCTAssertTrue(state.groundedURLs.contains(AgentCitationIntegrityGate.normalize("https://www.notion.so/pricing")))
        XCTAssertTrue(state.groundedURLs.contains(AgentCitationIntegrityGate.normalize("https://www.notion.com/pricing")))
        XCTAssertTrue(state.groundedURLs.contains(AgentCitationIntegrityGate.normalize("https://example.com/inside")))
        XCTAssertFalse(state.groundedURLs.contains(AgentCitationIntegrityGate.normalize("https://snippet.example.com/unread")))
        XCTAssertTrue(state.writtenWorkspacePaths.contains("brief.md"))
        XCTAssertTrue(state.writtenWorkspacePaths.contains("/tmp/brief.md"))
    }

    func testSeededProvenanceCoversUserMessageAndPriorTurns() {
        var state = AgentRunLoopState()
        var thread = ChatThread(title: "t")
        thread.messages.append(.init(role: .assistant, content: "Earlier I cited [a](https://prior.example.com/page)."))
        state.seedCitationProvenance(
            userMessage: "Also include https://user.example.com/tracker in the summary.",
            thread: thread
        )
        XCTAssertTrue(state.groundedURLs.contains(AgentCitationIntegrityGate.normalize("https://prior.example.com/page")))
        XCTAssertTrue(state.groundedURLs.contains(AgentCitationIntegrityGate.normalize("https://user.example.com/tracker")))
    }

    // MARK: - End-to-end recovery through the runner

    private actor ScriptedState {
        var steps: [AgentAction]
        init(_ steps: [AgentAction]) { self.steps = steps }
        func next() -> AgentAction {
            steps.isEmpty ? .say("out of steps") : steps.removeFirst()
        }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            await state.next()
        }
    }

    private func fetchStubRunner(llm: ScriptedClient) -> AgentRunner {
        var runner = AgentRunner(
            llm: llm,
            additionalToolDefinitions: [.webFetch]
        )
        runner.toolExecutionOverride = { call, _ in
            guard call.name == "host.web.fetch" else { return nil }
            return ToolResult(
                ok: true,
                stdout: "Fetched https://example.com/real (HTTP 200, text/html, 10 KB fetched, converted to markdown).\n\n# Real page"
            )
        }
        return runner
    }

    func testUngroundedCitationIsCorrectedAndCleanAnswerPasses() async throws {
        let root = try makeWorkspace()
        let fetch = ToolCall(name: "host.web.fetch", argumentsJSON: #"{"url":"https://example.com/real"}"#)
        let state = ScriptedState([
            .tool(fetch),
            .say("See [real](https://example.com/real) and [guessed](https://example.com/never-fetched)."),
            .say("See [real](https://example.com/real); the other page is unverified."),
        ])
        let runner = fetchStubRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "Research example.com and summarize.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        let final = try XCTUnwrap(result.thread.messages.last?.content)
        XCTAssertTrue(final.contains("unverified"))
        XCTAssertFalse(final.contains("never-fetched"))
        XCTAssertFalse(final.contains("⚠ Citation integrity"))
    }

    func testPersistentRefusalSurfacesIntegrityNoticeInsteadOfFailing() async throws {
        let root = try makeWorkspace()
        let fetch = ToolCall(name: "host.web.fetch", argumentsJSON: #"{"url":"https://example.com/real"}"#)
        let bad = AgentAction.say("See [guessed](https://example.com/never-fetched).")
        let state = ScriptedState([.tool(fetch), bad, bad, bad])
        let runner = fetchStubRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "Research example.com and summarize.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        let final = try XCTUnwrap(result.thread.messages.last?.content)
        XCTAssertTrue(final.contains("⚠ Citation integrity"))
        XCTAssertTrue(final.contains("https://example.com/never-fetched"))
    }

    func testCitationCorrectiveCannotEndRunOnBarePromiseSay() async throws {
        // Bypass proven by a review probe: the first corrective sample dodges the gate with a
        // link-free promise ("I'll fetch it now") — zero offenders would have passed it. The gate
        // must re-screen promises within its budget; here the second sample complies honestly.
        let root = try makeWorkspace()
        let fetch = ToolCall(name: "host.web.fetch", argumentsJSON: #"{"url":"https://example.com/real"}"#)
        let promise = "I'll fetch https://example.com/never-fetched now and verify the link."
        let state = ScriptedState([
            .tool(fetch),
            .say("See [guessed](https://example.com/never-fetched)."),
            .say(promise),
            .say("The claim is unverified; I could not confirm the page."),
        ])
        let runner = fetchStubRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "Research example.com and summarize.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        let final = try XCTUnwrap(result.thread.messages.last?.content)
        XCTAssertNotEqual(final, promise)
        XCTAssertTrue(final.contains("unverified"))
    }

    func testRunWithoutFetchesEndsUntouched() async throws {
        let root = try makeWorkspace()
        let state = ScriptedState([.say("The answer links [docs](https://example.com/docs).")])
        let runner = AgentRunner(llm: ScriptedClient(state: state))
        let result = try await runner.send(
            "What is the docs URL?",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )
        let final = try XCTUnwrap(result.thread.messages.last?.content)
        XCTAssertFalse(final.contains("⚠ Citation integrity"))
    }

    func testFollowUpTurnDoesNotFlagPriorTurnCitations() async throws {
        // The multi-turn finding: turn 1 fetched five pages and wrote the brief; turn 2 fetches
        // one new page. Turn-1 citations are grounded via the thread history seed.
        let root = try makeWorkspace()
        try "[t1](https://turn-one.example.com/page)".write(
            to: root.appendingPathComponent("brief.md"), atomically: true, encoding: .utf8
        )
        var thread = ChatThread(title: "t")
        thread.messages.append(.init(role: .user, content: "Build a brief and write brief.md"))
        thread.messages.append(.init(
            role: .assistant,
            content: "Wrote brief.md citing [t1](https://turn-one.example.com/page)."
        ))
        let fetch = ToolCall(name: "host.web.fetch", argumentsJSON: #"{"url":"https://example.com/real"}"#)
        let write = ToolCall(
            name: "host.file.write",
            argumentsJSON: try XCTUnwrap(String(
                data: JSONSerialization.data(withJSONObject: [
                    "path": "brief.md",
                    "content": "[t1](https://turn-one.example.com/page) and [new](https://example.com/real)",
                ]),
                encoding: .utf8
            ))
        )
        let state = ScriptedState([
            .tool(fetch),
            .tool(write),
            .say("Updated brief.md with the new section."),
        ])
        let runner = fetchStubRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "Add a section to the brief and write brief.md",
            in: thread,
            workspaceRoot: root
        )

        let final = try XCTUnwrap(result.thread.messages.last?.content)
        XCTAssertFalse(final.contains("⚠ Citation integrity"))
    }
}
