import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// Cline learning #1 (docs/CLINE_TOOL_LEARNINGS.md): corrective re-prompts escalate with the
/// failure count instead of repeating the same text. The final budgeted attempt switches to a
/// directive form that forbids repeating the response and offers numbered ways out.
final class AgentCorrectionEscalationTests: XCTestCase {
    func testFirstAttemptPassesBaseThrough() {
        let base = "Please write the file."
        XCTAssertEqual(
            AgentCorrectionEscalation.escalated(base, attempt: 0, limit: 2, alternatives: ["a"]),
            base
        )
    }

    func testFinalAttemptGetsDirectivePreambleWithNumberedAlternatives() {
        let escalated = AgentCorrectionEscalation.escalated(
            "Please write the file.",
            attempt: 1,
            limit: 2,
            alternatives: ["write it now", "explain what blocked you"]
        )
        XCTAssertTrue(escalated.contains("FINAL ATTEMPT (2 of 2)"))
        XCTAssertTrue(escalated.contains("Do NOT repeat that response"))
        XCTAssertTrue(escalated.contains("(1) write it now"))
        XCTAssertTrue(escalated.contains("(2) explain what blocked you"))
        XCTAssertTrue(escalated.contains("Please write the file."))
    }

    func testSingleAttemptBudgetNeverEscalates() {
        let base = "base"
        XCTAssertEqual(
            AgentCorrectionEscalation.escalated(base, attempt: 0, limit: 1, alternatives: ["a"]),
            base
        )
    }

    // MARK: - End-to-end: the deliverable gate's second corrective is escalated

    private actor PromptRecorder {
        var prompts: [String] = []
        var steps: [AgentAction]
        init(_ steps: [AgentAction]) { self.steps = steps }
        func next(_ userMessage: String) -> AgentAction {
            prompts.append(userMessage)
            return steps.isEmpty ? .say("out of steps") : steps.removeFirst()
        }
        func recorded() -> [String] { prompts }
    }

    private struct RecordingClient: LLMClient {
        let state: PromptRecorder
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            await state.next(userMessage)
        }
    }

    // MARK: - F31: a malformed corrective sample must not kill the run

    private actor ThrowingState {
        var steps: [Result<AgentAction, Error>]
        init(_ steps: [Result<AgentAction, Error>]) { self.steps = steps }
        func next() throws -> AgentAction {
            guard !steps.isEmpty else { return .say("out of steps") }
            return try steps.removeFirst().get()
        }
    }

    private struct ThrowingClient: LLMClient {
        let state: ThrowingState
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            try await state.next()
        }
    }

    func testMalformedCorrectiveSampleConsumesAttemptInsteadOfKillingRun() async throws {
        // Live F31: terminal say with the named deliverable missing → gate corrective sample
        // returns thinking-only garbage (invalidActionJSON). The run must NOT die on it; the
        // attempt is consumed and the gate reaches its honest terminal behavior.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("f31-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let state = ThrowingState([
            .success(.say("Done.")),
            .failure(TrustedRouterAgentError.invalidActionJSON("thinking-only garbage")),
            .failure(TrustedRouterAgentError.invalidActionJSON("more garbage")),
        ])
        let runner = AgentRunner(llm: ThrowingClient(state: state))
        do {
            _ = try await runner.send(
                "Search the folders and build index.md with a table.",
                in: ChatThread(title: "t"),
                workspaceRoot: root
            )
            XCTFail("expected missingNamedDeliverable")
        } catch AgentError.missingNamedDeliverable(let path) {
            XCTAssertEqual(path, "index.md")
        } catch {
            XCTFail("run died on the malformed sample instead of the gate's honest failure: \(error)")
        }
    }

    func testDeliverableGateSecondCorrectiveIsDirective() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("escalation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        // Three bare "Done." says: initial + two corrective samples, then the hard failure.
        let state = PromptRecorder([.say("Done."), .say("Done."), .say("Done.")])
        let runner = AgentRunner(llm: RecordingClient(state: state))
        do {
            _ = try await runner.send(
                "Search the folders and build index.md with a table.",
                in: ChatThread(title: "t"),
                workspaceRoot: root
            )
            XCTFail("expected missingNamedDeliverable")
        } catch AgentError.missingNamedDeliverable {
            // expected
        }

        let prompts = await state.recorded()
        let correctives = prompts.filter { $0.contains("index.md") && $0 != prompts.first }
        XCTAssertGreaterThanOrEqual(correctives.count, 2)
        XCTAssertFalse(try XCTUnwrap(correctives.first).contains("FINAL ATTEMPT"))
        XCTAssertTrue(try XCTUnwrap(correctives.last).contains("FINAL ATTEMPT"))
        XCTAssertTrue(try XCTUnwrap(correctives.last).contains("host.file.write"))
    }

    func testBoundedAuditEscalatesPassiveResponsesIntoValidatorAndCompletes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bounded-audit-escalation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let reportPath = "outputs/report.md"
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": reportPath,
                "content": "name,value\nalpha,1\nbeta,2\n",
            ])
        )
        let validator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 scripts/validate_report.py outputs/report.md",
            ])
        )
        let read = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": reportPath])
        )
        let state = PromptRecorder([
            .tool(write),
            .say("The report is complete."),
            .say("Validation is unnecessary."),
            .say("I already finished."),
            .tool(validator),
            .tool(read),
            .say("Completed and verified outputs/report.md."),
        ])
        let runner = AgentRunner(
            llm: RecordingClient(state: state),
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                return ToolResult(ok: true, stdout: "PASS")
            },
            maxToolSteps: 12,
            boundedRunFinalizationAfterSeconds: 0
        )

        let result = try await runner.send(
            "Create outputs/report.md with exactly two data rows, run a deterministic validator "
                + "against it, read it back, and report completion.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let prompts = await state.recorded()
        let auditPrompts = prompts.filter { $0.contains("reserved validation window") }
        let diagnostics = prompts.enumerated()
            .map { "[\($0.offset)] \($0.element)" }
            .joined(separator: "\n---\n")
        XCTAssertEqual(result.stopReason, .finished, diagnostics)
        XCTAssertEqual(result.toolResults.map(\.ok), [true, true], diagnostics)
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Completed and verified outputs/report.md.",
            diagnostics
        )
        XCTAssertTrue(prompts.contains {
            $0.contains("requested deliverable, deterministic audit, and readback are complete")
        }, diagnostics)
        XCTAssertGreaterThanOrEqual(auditPrompts.count, AgentCorrectiveTurnBudget.limit)
        XCTAssertFalse(try XCTUnwrap(auditPrompts.first).contains("FINAL ATTEMPT"))
        XCTAssertTrue(try XCTUnwrap(auditPrompts.last).contains("FINAL ATTEMPT (3 of 3)"))
        XCTAssertTrue(try XCTUnwrap(auditPrompts.last).contains("\"cmd\" argument"))
        XCTAssertTrue(try XCTUnwrap(auditPrompts.last).contains("host.shell.run"))
    }

    func testExhaustedPromisedWorkAfterSuccessfulReadGetsOneRunLevelContinuation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("promised-continuation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "source facts\n".write(
            to: root.appendingPathComponent("source.txt"),
            atomically: true,
            encoding: .utf8
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let state = ThrowingState([
            .success(.tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": "source.txt"])
            ))),
            .success(.say("I will now create report.md.")),
            .success(.say("I'll create report.md now.")),
            .success(.say("Let me write report.md.")),
            .success(.tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "report.md",
                    "content": "# Report\n\nSource facts summarized.\n",
                ])
            ))),
            .success(.say("Created report.md.")),
        ])
        let runner = AgentRunner(llm: ThrowingClient(state: state))

        let result = try await runner.send(
            "Read source.txt and write report.md.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.map(\.ok), [true, true])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("report.md").path))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("stopped at a promise")
        })
    }

    func testExhaustedPromisesAdvanceEachExplicitUnreadSourceBeforeModelContinuation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("promised-source-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("inputs"),
            withIntermediateDirectories: true
        )
        try "buyer: Morgan\n".write(
            to: root.appendingPathComponent("inputs/context.md"),
            atomically: true,
            encoding: .utf8
        )
        try "milestone,date\nsecurity review,2026-08-12\n".write(
            to: root.appendingPathComponent("inputs/data.csv"),
            atomically: true,
            encoding: .utf8
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let promise = AgentAction.say("I need to read the source files. Reading them now.")
        let state = ThrowingState([
            .success(.tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": "inputs/browser.html"])
            ))),
            .success(promise),
            .success(promise),
            .success(promise),
            .success(promise),
            .success(promise),
            .success(promise),
            .success(.tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "outputs/plan.md",
                    "content": "# Mutual action plan\n\nMorgan owns security review on 2026-08-12.\n",
                ])
            ))),
            .success(.say("Created outputs/plan.md.")),
        ])
        try "demo notes\n".write(
            to: root.appendingPathComponent("inputs/browser.html"),
            atomically: true,
            encoding: .utf8
        )
        let runner = AgentRunner(llm: ThrowingClient(state: state), maxToolSteps: 8)

        let result = try await runner.send(
            """
            Inspect the browser notes. Use the file read tool separately on `inputs/context.md` and \
            `inputs/data.csv`. Write the deliverable to `outputs/plan.md`. After writing, read it back.
            """,
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.map(\.ok), [true, true, true, true, true])
        XCTAssertEqual(
            result.thread.events.filter {
                $0.kind == .notice && $0.summary.contains("advanced an explicit requested source read")
            }.count,
            2
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("outputs/plan.md").path
        ))
    }
}
