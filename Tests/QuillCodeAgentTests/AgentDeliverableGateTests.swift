import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// F23 — shape-5 enforcement. Live failures this closes: a BFCL run that finished `generate` and
/// ended without the required RESULT.md, and a folder-index run that ended on a bare "Done." with
/// index.md never written. Both had "write <file>" verbatim in the task.
final class AgentDeliverableGateTests: XCTestCase {
    // MARK: - Extraction

    func testExtractsCreatedFilenames() {
        XCTAssertEqual(
            AgentDeliverableGate.requiredDeliverables(
                in: "Research this and write ./recommendation.md containing a comparison."
            ),
            ["recommendation.md"]
        )
        XCTAssertEqual(
            AgentDeliverableGate.requiredDeliverables(
                in: "build index.md with a table, and also produce summary.csv please"
            ),
            ["index.md", "summary.csv"]
        )
    }

    func testSourcePrepositionFilenamesAreNotDeliverables() {
        XCTAssertEqual(
            AgentDeliverableGate.requiredDeliverables(
                in: "Create a summary of report.pdf and write findings.md"
            ),
            ["findings.md"]
        )
        XCTAssertTrue(
            AgentDeliverableGate.requiredDeliverables(
                in: "Generate insights from sales.csv using config.yaml"
            ).isEmpty
        )
    }

    func testNegatedCreateVerbsAreNotDeliverables() {
        // The CI catch: "Do not write `forbidden.txt` with content `nope`." — the gate must never
        // force into existence a file the user explicitly forbade.
        XCTAssertTrue(
            AgentDeliverableGate.requiredDeliverables(
                in: "Do not write `forbidden.txt` with content `nope`."
            ).isEmpty
        )
        XCTAssertTrue(
            AgentDeliverableGate.requiredDeliverables(
                in: "Don't create debug.log, and never save temp.json anywhere."
            ).isEmpty
        )
        // A negation elsewhere must not suppress a REAL deliverable later in the message.
        XCTAssertEqual(
            AgentDeliverableGate.requiredDeliverables(
                in: "Do not touch the originals. Write summary.md with the results."
            ),
            ["summary.md"]
        )
    }

    func testPlainMentionsWithoutCreateVerbAreIgnored() {
        XCTAssertTrue(
            AgentDeliverableGate.requiredDeliverables(
                in: "The data lives in metrics.csv; tell me what changed."
            ).isEmpty
        )
    }

    func testQualifiedDeliverableCanonicalizesEarlierBareFilename() throws {
        let prompt = """
        Produce lost-demo-patterns.csv and a one-page summary.
        Save the complete primary deliverable to `outputs/wave5-213.md`.
        Also create the required supporting artifact: `outputs/lost-demo-patterns.csv`.
        """

        XCTAssertEqual(
            AgentDeliverableGate.requiredDeliverables(in: prompt),
            ["outputs/wave5-213.md", "outputs/lost-demo-patterns.csv"]
        )

        let root = try makeWorkspace()
        let outputs = root.appendingPathComponent("outputs", isDirectory: true)
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
        try "summary".write(
            to: outputs.appendingPathComponent("wave5-213.md"),
            atomically: true,
            encoding: .utf8
        )
        try "patterns".write(
            to: outputs.appendingPathComponent("lost-demo-patterns.csv"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(AgentDeliverableGate.missingDeliverables(in: prompt, workspaceRoot: root).isEmpty)
    }

    func testDistinctQualifiedPathsWithSameFilenameRemainRequired() {
        XCTAssertEqual(
            AgentDeliverableGate.requiredDeliverables(
                in: "Write current/report.md and create archive/report.md for comparison."
            ),
            ["current/report.md", "archive/report.md"]
        )
    }

    // MARK: - Existence gate

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deliverable-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testExistingDeliverableDoesNotFire() throws {
        let root = try makeWorkspace()
        try "done".write(to: root.appendingPathComponent("out.md"), atomically: true, encoding: .utf8)
        XCTAssertTrue(
            AgentDeliverableGate.missingDeliverables(in: "write out.md now", workspaceRoot: root).isEmpty
        )
    }

    func testMissingDeliverableFires() throws {
        let root = try makeWorkspace()
        XCTAssertEqual(
            AgentDeliverableGate.missingDeliverables(in: "write out.md now", workspaceRoot: root),
            ["out.md"]
        )
    }

    // MARK: - End-to-end recovery

    private actor ScriptedState {
        var steps: [AgentAction]
        let root: URL
        init(_ steps: [AgentAction], root: URL) { self.steps = steps; self.root = root }
        func next() -> AgentAction {
            guard !steps.isEmpty else { return .say("out of steps") }
            let step = steps.removeFirst()
            // Simulate the corrective sample actually writing the file when scripted to comply.
            if case .say(let text) = step, text == "WRITE_THEN_DONE" {
                try? "content".write(
                    to: root.appendingPathComponent("index.md"), atomically: true, encoding: .utf8
                )
                return .say("index.md is written and verified.")
            }
            return step
        }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            await state.next()
        }
    }

    func testBareDoneWithMissingDeliverableIsCorrectedAndRunSucceeds() async throws {
        let root = try makeWorkspace()
        // First sample: the live failure verbatim — "Done." with nothing written. The corrective
        // sample complies (writes the file), and the run ends cleanly.
        let state = ScriptedState([.say("Done."), .say("WRITE_THEN_DONE")], root: root)
        let runner = AgentRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "Search the folders and build index.md with a table of matches.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.md").path))
        XCTAssertTrue(result.thread.messages.contains { $0.content.contains("index.md is written") })
    }

    func testPersistentRefusalFailsHonestly() async throws {
        let root = try makeWorkspace()
        let state = ScriptedState([.say("Done."), .say("Done."), .say("Done.")], root: root)
        let runner = AgentRunner(llm: ScriptedClient(state: state))
        do {
            _ = try await runner.send(
                "Search the folders and build index.md with a table of matches.",
                in: ChatThread(title: "t"),
                workspaceRoot: root
            )
            XCTFail("expected missingNamedDeliverable")
        } catch AgentError.missingNamedDeliverable(let path) {
            XCTAssertEqual(path, "index.md")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRepeatedCallFinalizationAlsoPassesThroughTheGate() async throws {
        // F25 live failure: an enrichment run repeated a search, the repeated-call path
        // "finalized" with raw search results, and exited with the required CSV never written —
        // bypassing the gate entirely. The finalized say must be gated like any terminal say;
        // the corrective sample here writes the file via a real tool action.
        let root = try makeWorkspace()
        let search = ToolCall(name: "host.file.list", argumentsJSON: #"{"path":"."}"#)
        let write = ToolCall(
            name: "host.file.write",
            argumentsJSON: try XCTUnwrap(String(
                data: JSONSerialization.data(withJSONObject: [
                    "path": "./leads.csv", "content": "company\nStripe\n",
                ]),
                encoding: .utf8
            ))
        )
        let state = ScriptedState([
            .tool(search),
            .tool(search),        // repeat → finalization path
            .tool(write),         // corrective sample: write the missing deliverable
            .say("leads.csv written."),
        ], root: root)
        let runner = AgentRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "Search the folder and build leads.csv from what you find.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("leads.csv").path))
        XCTAssertTrue(result.thread.messages.contains { $0.content.contains("leads.csv written") })
    }

    func testSayWithNoNamedDeliverablesPassesUntouched() async throws {
        let root = try makeWorkspace()
        let state = ScriptedState([.say("The answer is 42.")], root: root)
        let runner = AgentRunner(llm: ScriptedClient(state: state))
        let result = try await runner.send(
            "What is six times seven?",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )
        XCTAssertTrue(result.thread.messages.contains { $0.content.contains("42") })
    }
}
