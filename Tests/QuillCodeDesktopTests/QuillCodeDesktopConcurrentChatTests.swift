import Foundation
import XCTest
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopConcurrentChatTests: XCTestCase {
    func testDesktopComposerRunsDifferentChatsInIndependentTaskSlots() async throws {
        let workspaceRoot = try makeTempDirectory()
        let gate = DesktopConcurrentPromptGate()
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: DesktopConcurrentPromptGateLLMClient(gate: gate))
        )
        let coordinator = QuillCodeDesktopComposerCoordinator()
        let tasks = QuillCodeDesktopTaskCoordinator()
        let firstThreadID = model.newChat()
        var firstDraft = "alpha desktop task"

        coordinator.send(
            draft: &firstDraft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: {}
        )
        try await waitUntil(timeoutSeconds: 1) {
            tasks.isSendRunning(threadID: firstThreadID)
                && model.isAgentRunActive(for: firstThreadID)
        }

        let secondThreadID = model.newChat()
        var secondDraft = "beta desktop task"
        coordinator.send(
            draft: &secondDraft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: {}
        )
        try await waitUntil(timeoutSeconds: 1) {
            tasks.runningSendThreadIDs == [firstThreadID, secondThreadID]
                && model.activeAgentRunThreadIDs == [firstThreadID, secondThreadID]
        }

        XCTAssertEqual(firstDraft, "")
        XCTAssertEqual(secondDraft, "")
        let alphaStarted = await gate.hasStarted("alpha desktop task")
        let betaStarted = await gate.hasStarted("beta desktop task")
        XCTAssertTrue(alphaStarted)
        XCTAssertTrue(betaStarted)

        await gate.release("beta desktop task")
        try await waitUntil(timeoutSeconds: 1) {
            !tasks.isSendRunning(threadID: secondThreadID)
                && tasks.isSendRunning(threadID: firstThreadID)
        }
        XCTAssertTrue(model.isAgentRunActive(for: firstThreadID))
        XCTAssertFalse(model.isAgentRunActive(for: secondThreadID))

        await gate.release("alpha desktop task")
        try await waitUntil(timeoutSeconds: 1) {
            tasks.runningSendThreadIDs.isEmpty && model.activeAgentRunThreadIDs.isEmpty
        }

        let first = try XCTUnwrap(model.root.threads.first { $0.id == firstThreadID })
        let second = try XCTUnwrap(model.root.threads.first { $0.id == secondThreadID })
        XCTAssertEqual(first.messages.last?.content, "Finished alpha desktop task")
        XCTAssertEqual(second.messages.last?.content, "Finished beta desktop task")
    }

    func testDesktopStopAllCancelsEveryRunningChat() async throws {
        let workspaceRoot = try makeTempDirectory()
        let gate = DesktopConcurrentPromptGate()
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: DesktopConcurrentPromptGateLLMClient(gate: gate))
        )
        let composer = QuillCodeDesktopComposerCoordinator()
        let tasks = QuillCodeDesktopTaskCoordinator()
        let firstThreadID = model.newChat()
        var firstDraft = "alpha stoppable task"
        composer.send(
            draft: &firstDraft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: {}
        )
        try await waitUntil(timeoutSeconds: 1) {
            model.isAgentRunActive(for: firstThreadID)
        }

        let secondThreadID = model.newChat()
        var secondDraft = "beta stoppable task"
        composer.send(
            draft: &secondDraft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: {}
        )
        try await waitUntil(timeoutSeconds: 1) {
            tasks.runningSendThreadIDs == [firstThreadID, secondThreadID]
                && model.activeAgentRunThreadIDs == [firstThreadID, secondThreadID]
        }

        var localDraft = "unsent local text"
        QuillCodeDesktopActiveWorkCoordinator().stopAll(
            draft: &localDraft,
            model: model,
            tasks: tasks,
            refresh: {}
        )

        XCTAssertTrue(tasks.runningSendThreadIDs.isEmpty)
        XCTAssertTrue(model.activeAgentRunThreadIDs.isEmpty)
        XCTAssertEqual(model.root.topBar.agentStatus, TopBarAgentStatusLabel.stopped)
        XCTAssertEqual(localDraft, "")

        await gate.release("alpha stoppable task")
        await gate.release("beta stoppable task")
        try await waitUntil(timeoutSeconds: 1) {
            [firstThreadID, secondThreadID].allSatisfy { threadID in
                model.root.threads.first(where: { $0.id == threadID })?.events.contains {
                    $0.kind == .notice && $0.summary == "Stopped by user"
                } == true
            }
        }
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for desktop condition", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeConcurrentChatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private actor DesktopConcurrentPromptGate {
    private var started: Set<String> = []
    private var released: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func wait(for prompt: String) async {
        started.insert(prompt)
        if released.remove(prompt) != nil { return }
        await withCheckedContinuation { continuation in
            waiters[prompt, default: []].append(continuation)
        }
    }

    func release(_ prompt: String) {
        let continuations = waiters.removeValue(forKey: prompt) ?? []
        if continuations.isEmpty {
            released.insert(prompt)
        } else {
            continuations.forEach { $0.resume() }
        }
    }

    func hasStarted(_ prompt: String) -> Bool {
        started.contains(prompt)
    }
}

private struct DesktopConcurrentPromptGateLLMClient: LLMClient {
    var gate: DesktopConcurrentPromptGate

    func nextAction(
        thread _: ChatThread,
        userMessage: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        await gate.wait(for: userMessage)
        return .say("Finished \(userMessage)")
    }
}
