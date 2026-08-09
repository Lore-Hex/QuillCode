import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceSubagentModelWorkerTests: XCTestCase {
    func testRunReturnsCollapsedAgentSummary() async throws {
        let root = try makeQuillCodeTestDirectory()
        let worker = makeWorker(
            root: root,
            actions: [.say("  Inspected the parser\n  and found two edge cases.  ")]
        )

        let summary = try await worker.run(
            WorkspaceSubagentJob(name: "Explorer", role: "inspect code", objective: "validate release")
        )

        XCTAssertEqual(summary, "Inspected the parser and found two edge cases.")
    }

    func testRunFallsBackToRoleForEmptyAgentSummary() async throws {
        let root = try makeQuillCodeTestDirectory()
        let worker = makeWorker(root: root, actions: [.say("   \n  ")])

        let summary = try await worker.run(
            WorkspaceSubagentJob(name: "Verifier", role: "run focused tests", objective: "ship the release")
        )

        XCTAssertEqual(summary, "Completed run focused tests")
    }

    func testRunExecutesToolsAndContinuesToFinalAnswer() async throws {
        let root = try makeQuillCodeTestDirectory()
        let marker = root.appendingPathComponent("subagent.txt")
        let worker = makeWorker(
            root: root,
            actions: [
                .tool(ToolCall(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "subagent.txt",
                        "content": "hello from subagent\n"
                    ])
                )),
                .say("Created subagent.txt and verified the write.")
            ]
        )

        let summary = try await worker.run(
            WorkspaceSubagentJob(name: "Builder", role: "create the marker", objective: "prepare fixture")
        )

        XCTAssertEqual(summary, "Created subagent.txt and verified the write.")
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "hello from subagent\n")
    }

    func testRunBuildsBoundedRedactedTranscriptWithoutRepeatingPrompt() async throws {
        let root = try makeQuillCodeTestDirectory()
        let secret = "sk-SYNTHETIC_SUBAGENT_SECRET_123456"
        let worker = makeWorker(
            root: root,
            actions: [
                .tool(ToolCall(
                    name: ToolDefinition.shellRun.name,
                    argumentsJSON: ToolArguments.json(["cmd": "printf '\(secret)' >/dev/null"])
                )),
                .say("Verified the worker command completed.")
            ]
        )

        let result = try await worker.runWithTranscript(
            WorkspaceSubagentJob(name: "Verifier", role: "run a check", objective: "private objective")
        )

        XCTAssertEqual(result.summary, "Verified the worker command completed.")
        XCTAssertEqual(result.transcript.map(\.kind), [.tool, .assistant])
        XCTAssertEqual(result.transcript.first?.title, "Shell command")
        XCTAssertEqual(result.transcript.first?.statusLabel, "Done")
        XCTAssertTrue(result.transcript.first?.detail.contains("[redacted]") == true)
        XCTAssertTrue(result.transcript.last?.detail.contains("Verified the worker") == true)
        XCTAssertFalse(result.transcript.map(\.detail).joined().contains(secret))
        XCTAssertFalse(result.transcript.map(\.detail).joined().contains("private objective"))
    }

    func testRunPausesForApprovalAndResumesTheExactWorker() async throws {
        let root = try makeQuillCodeTestDirectory()
        let parent = ChatThread(mode: .review)
        let worker = makeWorker(
            root: root,
            actions: [
                .tool(ToolCall(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json(["path": "blocked.txt", "content": "no"])
                )),
                .say("Done.")
            ],
            safety: StaticSafetyReviewer(),
            parentThread: parent
        )

        let job = WorkspaceSubagentJob(
            name: "Builder",
            role: "write a file",
            objective: "test review mode"
        )
        let pause: WorkspaceSubagentApprovalPause
        do {
            _ = try await worker.runWithTranscript(job)
            XCTFail("Expected review mode to block an unapproved delegated write")
            return
        } catch let caught as WorkspaceSubagentApprovalPause {
            pause = caught
        }

        XCTAssertEqual(pause.pendingApproval.request.toolCall.name, ToolDefinition.fileWrite.name)
        XCTAssertEqual(pause.pendingApproval.heldToolCall?.name, ToolDefinition.fileWrite.name)
        XCTAssertTrue(pause.pendingApproval.request.reason.contains("explicit approval"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("blocked.txt").path))

        let resumed = try await worker.resume(pause, job: job)

        XCTAssertEqual(resumed.summary, "Done.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("blocked.txt").path))
        XCTAssertTrue(resumed.transcript.contains { $0.kind == .tool && $0.statusLabel == "Done" })
    }

    func testRunInheritsParentProjectContext() async throws {
        let root = try makeQuillCodeTestDirectory()
        let projectID = UUID()
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "Project instructions",
            content: "Follow project rules.",
            byteCount: 21
        )
        let memory = MemoryNote(
            id: "memory-1",
            scope: .project,
            title: "Parser",
            content: "Use the existing parser.",
            relativePath: "parser.md",
            byteCount: 24
        )
        let parent = ChatThread(
            projectID: projectID,
            mode: .readOnly,
            model: "acme/model",
            instructions: [instruction],
            memories: [memory]
        )
        let recorder = SubagentRecordingActionQueue(actions: [.say("done")])
        let worker = makeWorker(
            root: root,
            llm: SubagentRecordingLLMClient(state: recorder),
            parentThread: parent
        )

        _ = try await worker.run(
            WorkspaceSubagentJob(name: "Explorer", role: "inspect", objective: "audit")
        )

        let recordedThread = await recorder.latestThread()
        let observed = try XCTUnwrap(recordedThread)
        XCTAssertEqual(observed.projectID, projectID)
        XCTAssertEqual(observed.mode, .readOnly)
        XCTAssertEqual(observed.model, "acme/model")
        XCTAssertEqual(observed.instructions, [instruction])
        XCTAssertEqual(observed.memories, [memory])
        let tools = await recorder.latestTools()
        XCTAssertTrue(tools.contains { $0.name == ToolDefinition.fileRead.name })
    }

    func testPromptIncludesObjectiveRoleAndAutonomousToolGuidance() {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(
            objective: "validate release",
            job: WorkspaceSubagentJob(name: "Explorer", role: "inspect code")
        )

        XCTAssertTrue(prompt.contains("validate release"))
        XCTAssertTrue(prompt.contains("inspect code"))
        XCTAssertTrue(prompt.contains("Explorer"))
        XCTAssertTrue(prompt.contains("Work autonomously with the available tools"))
        XCTAssertTrue(prompt.contains("Do not merely announce what you intend to do"))
        XCTAssertTrue(prompt.contains("Do not finish while any recoverable part"))
        XCTAssertTrue(prompt.contains("preserve each useful fact with its source URL"))
        XCTAssertTrue(prompt.contains("two focused"))
        XCTAssertTrue(prompt.contains("switch to another"))
        XCTAssertTrue(prompt.contains("source or extraction method instead of rewriting the query again"))
        XCTAssertTrue(prompt.contains("Prefer direct evidence gathering over building helper"))
        XCTAssertTrue(prompt.contains("COMPLETE:"))
        XCTAssertTrue(prompt.contains("BLOCKED:"))
        XCTAssertFalse(prompt.contains("any remaining next steps"))
        XCTAssertFalse(prompt.contains(#"{"type":"say""#))
    }

    func testExplicitBlockedResultIsNotReportedAsDone() async throws {
        let root = try makeQuillCodeTestDirectory()
        let worker = makeWorker(
            root: root,
            actions: [.say("BLOCKED: the required account is signed out after two login checks.")]
        )

        let result = try await worker.runWithTranscript(
            WorkspaceSubagentJob(name: "Verifier", role: "inspect the private account", objective: "audit")
        )

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.summary.contains("BLOCKED:"))
    }

    func testCancellationSummaryPreservesLatestWorkerNote() {
        let thread = ChatThread(messages: [
            ChatMessage(role: .assistant, content: "Confirmed Q1 revenue from the official release.\nQ2 remains unresolved.")
        ])

        XCTAssertEqual(
            AgentWorkspaceSubagentWorker.cancellationSummary(from: thread),
            "Cancelled at the delegation deadline. Latest worker note: Confirmed Q1 revenue from the official release. Q2 remains unresolved."
        )
    }

    func testCancellationSummaryExplainsMissingFinalNote() {
        let thread = ChatThread(messages: [
            ChatMessage(role: .user, content: "Research quarterly revenue.")
        ])

        XCTAssertEqual(
            AgentWorkspaceSubagentWorker.cancellationSummary(from: thread),
            "Cancelled at the delegation deadline before the worker produced a final summary."
        )
    }

    func testIncompleteTerminalNarrationIsNotReportedAsDone() {
        let stalls = [
            "COMPLETE: I need Q4 revenue to finish the requested set.",
            "The IR page uses JavaScript. Fetching the Q2 release next for revenue figures.",
            "I found the annual report. I will try Nasdaq next for the missing quarter.",
            "The first source was blocked; let me search the investor-relations archive.",
            "GitLab Q1 FY2026 confirmed. Now retrieving Q2 FY2026 results for the missing figure.",
            "COMPLETE: I have not yet obtained reliable total revenue figures for three quarters.",
            "The role is not fully complete; I need to fetch the remaining releases.",
            "Starting research. I have Q1, and now I need Q2 through Q4.",
            "Q2 revenue is confirmed. I need to gather Q3 and Q4 next.",
            "The query windows returned only the headline ($333.9M for Q4 2025) and not the full GAAP revenue table. Fetching the alternate press-release URL to extract the complete fiscal-year and quarterly GAAP revenue figures.",
            "I have all four FY2026 quarters, but I need to verify the",
            "The previous attempts failed because the focused-evidence fetches kept truncating before the",
            "COMPLETE: Need the four Q figures. One Q4 FY2026 figure found: $205.6M. Need to fetch remaining quarters.",
            "The prior source repeated the same result. I'll switch to a different source: TipRanks for historical quarterly values.",
        ]

        for stall in stalls {
            XCTAssertEqual(WorkspaceSubagentTerminalStatus.status(for: stall), .failed)
        }
    }

    func testExplicitCompleteMarkerIsReportedAsDone() {
        XCTAssertEqual(
            WorkspaceSubagentTerminalStatus.status(
                for: "COMPLETE: Verified all four quarters against official investor-relations releases."
            ),
            .completed
        )
    }

    func testCancellationSummaryRecoversGroundedReasoningAndToolEvidence() throws {
        let feedback = AgentToolFeedback(
            toolCall: ToolCall(
                name: ToolDefinition.webFetch.name,
                argumentsJSON: #"{"url":"https://ir.example.test/q1"}"#
            ),
            result: ToolResult(
                ok: true,
                stdout: "Fetched https://ir.example.test/q1. Q1 revenue was $214.5 million."
            )
        )
        let thread = ChatThread(
            messages: [
                ChatMessage(role: .tool, content: try JSONHelpers.encodePretty(feedback)),
                ChatMessage(role: .assistant, content: "I have the values, but I need to verify the"),
            ],
            events: [
                ThreadEvent(
                    kind: .notice,
                    summary: "Thinking: Q1 $214.5M and Q2 $236.0M reconcile to the official filing."
                ),
            ]
        )

        let summary = AgentWorkspaceSubagentWorker.cancellationSummary(from: thread)

        XCTAssertTrue(summary.contains("Recovered grounded evidence:"))
        XCTAssertTrue(summary.contains("Q1 $214.5M"))
        XCTAssertTrue(summary.contains("https://ir.example.test/q1"))
    }

    func testFinishedWorkerWithAbruptFinalRecoversGroundedToolEvidence() async throws {
        let root = try makeQuillCodeTestDirectory()
        let evidence = root.appendingPathComponent("gitlab-q2.txt")
        try "Official source https://ir.example.test/q2: Total revenue was $236.0 million."
            .write(to: evidence, atomically: true, encoding: .utf8)
        let worker = makeWorker(
            root: root,
            actions: [
                .tool(ToolCall(
                    name: ToolDefinition.fileRead.name,
                    argumentsJSON: ToolArguments.json(["path": "gitlab-q2.txt"])
                )),
                .say("The previous attempts failed because the focused-evidence fetches kept truncating before the"),
            ]
        )

        let result = try await worker.runWithTranscript(
            WorkspaceSubagentJob(name: "Researcher", role: "gather every quarter", objective: "compare revenue")
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.summary.contains("Recovered grounded evidence:"))
        XCTAssertTrue(result.summary.contains("https://ir.example.test/q2"))
        XCTAssertTrue(result.summary.contains("$236.0 million"))
    }

    func testEvidenceDigestPrioritizesDistinctValueBearingSourcesOverTrailingNavigation() throws {
        func toolMessage(url: String, output: String) throws -> ChatMessage {
            let feedback = AgentToolFeedback(
                toolCall: ToolCall(
                    name: ToolDefinition.webFetch.name,
                    argumentsJSON: ToolArguments.json(["url": url])
                ),
                result: ToolResult(ok: true, stdout: output)
            )
            return ChatMessage(role: .tool, content: try JSONHelpers.encodePretty(feedback))
        }

        let thread = ChatThread(messages: [
            try toolMessage(url: "https://ir.example.test/q1", output: "Navigation only."),
            try toolMessage(url: "https://ir.example.test/q1", output: "Q1 total revenue was $214.5 million."),
            try toolMessage(url: "https://ir.example.test/q2", output: "Q2 total revenue was $236.0 million."),
            try toolMessage(url: "https://ir.example.test/q3", output: "Q3 total revenue was $244.4 million."),
            try toolMessage(url: "https://ir.example.test/q4", output: "Q4 total revenue was $260.4 million."),
            try toolMessage(url: "https://example.test/nav-1", output: "Fetched page navigation and footer."),
            try toolMessage(url: "https://example.test/nav-2", output: "Fetched page navigation and footer."),
        ])

        let summary = try XCTUnwrap(WorkspaceSubagentEvidenceDigest.summary(from: thread))

        XCTAssertTrue(summary.contains("$214.5 million"))
        XCTAssertTrue(summary.contains("$236.0 million"))
        XCTAssertTrue(summary.contains("$244.4 million"))
        XCTAssertTrue(summary.contains("$260.4 million"))
        XCTAssertFalse(summary.contains("page navigation and footer"))
    }

    func testToolStepCeilingIsNotReportedAsCompleted() async throws {
        let root = try makeQuillCodeTestDirectory()
        let worker = makeWorker(
            root: root,
            actions: [.tool(ToolCall(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": "missing.txt"])
            ))],
            maxToolSteps: 1
        )

        let result = try await worker.runWithTranscript(
            WorkspaceSubagentJob(name: "Researcher", role: "gather all quarters", objective: "compare revenue")
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.summary.contains("1-step tool limit"))
        XCTAssertTrue(result.summary.contains("Latest evidence:"))
    }

    func testPromptOffersOptionalDelegationViaTheParsedMarker() {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(
            objective: "ship release",
            job: WorkspaceSubagentJob(name: "Builder", role: "build")
        )

        XCTAssertTrue(prompt.contains(WorkspaceSubagentSpawnDirectiveParser.openMarker))
        XCTAssertTrue(prompt.contains("only if"))
        XCTAssertTrue(prompt.contains("sparingly"))
        let parsed = WorkspaceSubagentSpawnDirectiveParser.parse(
            "[[DELEGATE: short name | what that subagent should do]]"
        )
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.name, "short name")
        XCTAssertEqual(parsed.first?.role, "what that subagent should do")
    }

    func testPromptIncludesPrerequisiteResultsWhenPresent() {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(
            objective: "ship release",
            job: WorkspaceSubagentJob(
                name: "Verifier",
                role: "run tests",
                dependsOn: ["Builder"],
                priorResults: [WorkspaceSubagentPriorResult(
                    name: "Builder",
                    summary: "compiled the app cleanly"
                )]
            )
        )

        XCTAssertTrue(prompt.contains("Results from the prerequisite subagents you depend on:"))
        XCTAssertTrue(prompt.contains("- Builder: compiled the app cleanly"))
    }

    func testPromptIncludesNestedPlanPathWhenPresent() {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(
            objective: "ship interface",
            job: WorkspaceSubagentJob(
                name: "Frontend/Verifier",
                role: "test click targets",
                groupPath: ["Frontend"]
            )
        )

        XCTAssertTrue(prompt.contains("Nested plan path: Frontend / Verifier"))
        XCTAssertTrue(prompt.contains("Parent group: Frontend"))
    }

    func testPromptOmitsPrerequisiteSectionForRootJobs() {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(
            objective: "ship release",
            job: WorkspaceSubagentJob(name: "Builder", role: "compile app")
        )

        XCTAssertFalse(prompt.contains("Results from the prerequisite subagents"))
    }

    func testRunPropagatesClientErrors() async throws {
        let root = try makeQuillCodeTestDirectory()
        let worker = makeWorker(root: root, llm: SubagentThrowingLLMClient())

        do {
            _ = try await worker.run(
                WorkspaceSubagentJob(name: "Explorer", role: "inspect code", objective: "validate release")
            )
            XCTFail("Expected the worker to propagate the client error")
        } catch {
            XCTAssertTrue(error is SubagentThrowingLLMClient.Failure)
        }
    }

    private func makeWorker(
        root: URL,
        actions: [AgentAction],
        safety: any SafetyReviewer = SubagentAlwaysApprovingSafetyReviewer(),
        parentThread: ChatThread = ChatThread(),
        maxToolSteps: Int = AgentRunner.defaultMaxToolSteps
    ) -> AgentWorkspaceSubagentWorker {
        makeWorker(
            root: root,
            llm: SubagentRecordingLLMClient(state: SubagentRecordingActionQueue(actions: actions)),
            safety: safety,
            parentThread: parentThread,
            maxToolSteps: maxToolSteps
        )
    }

    private func makeWorker(
        root: URL,
        llm: any LLMClient,
        safety: any SafetyReviewer = SubagentAlwaysApprovingSafetyReviewer(),
        parentThread: ChatThread = ChatThread(),
        maxToolSteps: Int = AgentRunner.defaultMaxToolSteps
    ) -> AgentWorkspaceSubagentWorker {
        let factory = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(llm: llm, safety: safety, maxToolSteps: maxToolSteps),
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: root
        )
        return AgentWorkspaceSubagentWorker(
            sessionFactory: factory,
            parentThread: parentThread
        )
    }
}

private actor SubagentRecordingActionQueue {
    private var actions: [AgentAction]
    private var thread: ChatThread?
    private var tools: [ToolDefinition] = []

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func next(thread: ChatThread, tools: [ToolDefinition]) throws -> AgentAction {
        self.thread = thread
        self.tools = tools
        guard !actions.isEmpty else {
            throw SubagentThrowingLLMClient.Failure()
        }
        return actions.removeFirst()
    }

    func latestThread() -> ChatThread? {
        thread
    }

    func latestTools() -> [ToolDefinition] {
        tools
    }
}

private struct SubagentRecordingLLMClient: LLMClient {
    var state: SubagentRecordingActionQueue

    func nextAction(
        thread: ChatThread,
        userMessage _: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        try await state.next(thread: thread, tools: tools)
    }
}

private struct SubagentAlwaysApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        SafetyReview(
            verdict: .approve,
            rationale: "Approved in the focused subagent test.",
            userIntentMatched: true
        )
    }
}

private struct SubagentThrowingLLMClient: LLMClient {
    struct Failure: Error {}

    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        throw Failure()
    }
}
