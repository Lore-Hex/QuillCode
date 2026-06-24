import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceAgentSendSessionTests: XCTestCase {
    func testRunReturnsCompletedThreadWithoutSavedMemory() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let thread = ChatThread(title: "New chat")
        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: thread,
            runner: AgentRunner(llm: SequenceLLMClient(actions: [.say("hello")])),
            workspaceRoot: workspaceRoot
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.id, thread.id)
        XCTAssertFalse(result.savedMemory)
        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(result.thread.messages.map(\.content), ["say hello", "hello"])
        XCTAssertEqual(result.thread.title, "say hello")
    }

    func testRunReportsProgressForTheSessionThread() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let thread = ChatThread(title: "Progress")
        let recorder = ProgressRecorder()
        let session = WorkspaceAgentSendSession(
            prompt: "stream",
            thread: thread,
            runner: AgentRunner(llm: SequenceLLMClient(actions: [.say("done")])),
            workspaceRoot: workspaceRoot
        )

        _ = try await session.run { progressThread in
            await recorder.record(progressThread.id)
        }

        let ids = await recorder.ids
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(Set(ids), [session.threadID])
    }

    func testRunReportsSavedMemoryWhenMemoryToolCompletes() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let memoryRoot = try makeQuillCodeTestDirectory()
        let rememberCall = ToolCall(
            name: ToolDefinition.memoryRemember.name,
            argumentsJSON: ToolArguments.json(["content": "Prefer concise status updates."])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(rememberCall),
                .say("remembered")
            ]),
            baseToolDefinitions: [],
            additionalToolDefinitions: [ToolDefinition.memoryRemember],
            toolExecutionOverride: WorkspaceMemoryRememberToolExecutor.executionOverride(directory: memoryRoot),
            maxToolSteps: 3
        )
        let session = WorkspaceAgentSendSession(
            prompt: "remember this",
            thread: ChatThread(title: "Memory"),
            runner: runner,
            workspaceRoot: workspaceRoot
        )

        let result = try await session.run()

        XCTAssertTrue(result.savedMemory)
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted &&
                $0.summary == "\(ToolDefinition.memoryRemember.name) completed"
        })
        let memoryFiles = try FileManager.default.contentsOfDirectory(
            at: memoryRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(memoryFiles.count, 1)
    }
}

private actor ProgressRecorder {
    private(set) var ids: [UUID] = []

    func record(_ id: UUID) {
        ids.append(id)
    }
}

private actor SequenceLLMState {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func next() -> AgentAction {
        guard !actions.isEmpty else {
            return .say("Done.")
        }
        return actions.removeFirst()
    }
}

private struct SequenceLLMClient: LLMClient {
    private let state: SequenceLLMState

    init(actions: [AgentAction]) {
        self.state = SequenceLLMState(actions: actions)
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        await state.next()
    }
}
