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

    func testRunCanUsePreRecordedUserMessageWithoutDuplicatingIt() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        var thread = ChatThread(title: "New chat")
        thread.messages.append(ChatMessage(role: .user, content: "say hello"))
        thread.events.append(ThreadEvent(kind: .message, summary: "say hello"))
        thread.title = "say hello"
        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: thread,
            runner: AgentRunner(llm: SequenceLLMClient(actions: [.say("hello")])),
            workspaceRoot: workspaceRoot,
            recordsUserMessage: false
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(result.thread.messages.map(\.content), ["say hello", "hello"])
        XCTAssertEqual(result.thread.events.filter { $0.kind == .message }.map(\.summary), ["say hello", "hello"])
    }

    func testRunDefaultsToRecordingUserMessage() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: ChatThread(title: "New chat"),
            runner: AgentRunner(llm: SequenceLLMClient(actions: [.say("hello")])),
            workspaceRoot: workspaceRoot
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages.map(\.content), ["say hello", "hello"])
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

    func testRunExecutesProjectHooksAroundAgentSend() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let beforeDirectory = try createHookDirectory(
            named: ".quillcode/hooks/before-agent-run",
            in: workspaceRoot
        )
        let afterDirectory = try createHookDirectory(
            named: ".quillcode/hooks/after-agent-run",
            in: workspaceRoot
        )
        try "printf before > before.txt".write(
            to: beforeDirectory.appendingPathComponent("01-before.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "printf after > after.txt".write(
            to: afterDirectory.appendingPathComponent("99-after.sh"),
            atomically: true,
            encoding: .utf8
        )
        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: ChatThread(title: "New chat"),
            runner: AgentRunner(llm: SequenceLLMClient(actions: [.say("hello")])),
            workspaceRoot: workspaceRoot,
            runHooks: ProjectRunHookLoader.load(from: workspaceRoot)
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(result.thread.messages.map(\.content), ["say hello", "hello"])
        XCTAssertEqual(
            try String(contentsOf: workspaceRoot.appendingPathComponent("before.txt"), encoding: .utf8),
            "before"
        )
        XCTAssertEqual(
            try String(contentsOf: workspaceRoot.appendingPathComponent("after.txt"), encoding: .utf8),
            "after"
        )
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolCompleted }.count, 2)
    }

    func testBeforeRunHookFailureStopsAgentSend() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let beforeDirectory = try createHookDirectory(
            named: ".quillcode/hooks/before-agent-run",
            in: workspaceRoot
        )
        try "echo nope >&2; exit 7".write(
            to: beforeDirectory.appendingPathComponent("01-before.sh"),
            atomically: true,
            encoding: .utf8
        )
        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: ChatThread(title: "New chat"),
            runner: AgentRunner(llm: SequenceLLMClient(actions: [.say("should not run")])),
            workspaceRoot: workspaceRoot,
            runHooks: ProjectRunHookLoader.load(from: workspaceRoot)
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(result.thread.messages[0].content, "say hello")
        XCTAssertTrue(result.thread.messages[1].content.contains("Before-run hook failed"))
        XCTAssertTrue(result.thread.messages[1].content.contains("nope"))
        XCTAssertFalse(result.thread.messages.contains { $0.content == "should not run" })
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolFailed }.count, 1)
    }

    func testAfterRunHookFailureKeepsAgentAnswerAndReportsFailure() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let afterDirectory = try createHookDirectory(
            named: ".quillcode/hooks/after-agent-run",
            in: workspaceRoot
        )
        try "echo cleanup failed >&2; exit 9".write(
            to: afterDirectory.appendingPathComponent("99-after.sh"),
            atomically: true,
            encoding: .utf8
        )
        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: ChatThread(title: "New chat"),
            runner: AgentRunner(llm: SequenceLLMClient(actions: [.say("hello")])),
            workspaceRoot: workspaceRoot,
            runHooks: ProjectRunHookLoader.load(from: workspaceRoot)
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(result.thread.messages[1].content, "hello")
        XCTAssertTrue(result.thread.messages[2].content.contains("After-run hook failed"))
        XCTAssertTrue(result.thread.messages[2].content.contains("cleanup failed"))
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolFailed }.count, 1)
    }
}

private func createHookDirectory(named relativePath: String, in root: URL) throws -> URL {
    let directory = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
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
