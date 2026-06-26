import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentSendTaskCoordinatorTests: XCTestCase {
    func testRunReturnsCompletedOutcome() async throws {
        let thread = ChatThread(title: "Agent")
        let coordinator = try makeCoordinator(
            prompt: "say hi",
            thread: thread,
            runner: AgentRunner(llm: FixedSayLLMClient(message: "hi"))
        )

        let outcome = await coordinator.run()

        guard case .completed(let result) = outcome else {
            return XCTFail("Expected completed outcome, got \(outcome)")
        }
        XCTAssertEqual(result.thread.id, thread.id)
        XCTAssertEqual(result.thread.messages.map(\.content), ["say hi", "hi"])
        XCTAssertFalse(result.savedMemory)
    }

    func testRunReportsProgressThroughSession() async throws {
        let thread = ChatThread(title: "Progress")
        let recorder = ProgressRecorder()
        let coordinator = try makeCoordinator(
            prompt: "stream",
            thread: thread,
            runner: AgentRunner(llm: FixedSayLLMClient(message: "done"))
        )

        _ = await coordinator.run { progressThread in
            await recorder.record(progressThread.id)
        }

        let ids = await recorder.ids
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(Set(ids), [thread.id])
    }

    func testRunConvertsCancellationToStoppedOutcome() async throws {
        let thread = ChatThread(title: "Cancel")
        let coordinator = try makeCoordinator(
            prompt: "wait",
            thread: thread,
            runner: AgentRunner(llm: NeverReturningLLMClient())
        )

        let task = Task {
            await coordinator.run()
        }
        task.cancel()

        let outcome = await task.value
        guard case .cancelled(let cancellation) = outcome else {
            return XCTFail("Expected cancelled outcome, got \(outcome)")
        }
        XCTAssertEqual(cancellation.userPrompt, "wait")
        XCTAssertEqual(cancellation.threadID, thread.id)
    }

    func testRunConvertsRuntimeErrorToFailedOutcome() async throws {
        let coordinator = try makeCoordinator(
            prompt: "fail",
            runner: AgentRunner(llm: ThrowingLLMClient(error: TestLLMError.offline))
        )

        let outcome = await coordinator.run()

        guard case .failed(let error) = outcome else {
            return XCTFail("Expected failed outcome, got \(outcome)")
        }
        XCTAssertEqual(String(describing: error), String(describing: TestLLMError.offline))
    }

    private func makeCoordinator(
        prompt: String,
        thread: ChatThread = ChatThread(title: "Agent"),
        runner: AgentRunner
    ) throws -> WorkspaceAgentSendTaskCoordinator {
        let start = WorkspaceAgentSendStartPlanner.started(
            prompt: prompt,
            thread: thread,
            composer: ComposerState(draft: prompt)
        )
        let session = WorkspaceAgentSendSession(
            prompt: start.prompt,
            thread: start.thread,
            runner: runner,
            workspaceRoot: try makeQuillCodeTestDirectory(),
            recordsUserMessage: false
        )
        return WorkspaceAgentSendTaskCoordinator(start: start, session: session)
    }
}

private actor ProgressRecorder {
    private(set) var ids: [UUID] = []

    func record(_ id: UUID) {
        ids.append(id)
    }
}

private struct FixedSayLLMClient: LLMClient {
    var message: String

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .say(message)
    }
}

private struct NeverReturningLLMClient: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return .say("done")
    }
}

private enum TestLLMError: Error {
    case offline
}

private struct ThrowingLLMClient: LLMClient {
    var error: any Error

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw error
    }
}
