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
        XCTAssertFalse(prompt.contains(#"{"type":"say""#))
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
        parentThread: ChatThread = ChatThread()
    ) -> AgentWorkspaceSubagentWorker {
        makeWorker(
            root: root,
            llm: SubagentRecordingLLMClient(state: SubagentRecordingActionQueue(actions: actions)),
            safety: safety,
            parentThread: parentThread
        )
    }

    private func makeWorker(
        root: URL,
        llm: any LLMClient,
        safety: any SafetyReviewer = SubagentAlwaysApprovingSafetyReviewer(),
        parentThread: ChatThread = ChatThread()
    ) -> AgentWorkspaceSubagentWorker {
        let factory = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(llm: llm, safety: safety),
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
