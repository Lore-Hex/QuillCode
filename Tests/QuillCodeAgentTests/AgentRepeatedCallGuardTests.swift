import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// Cline learning #2 (graded loop detection): the FIRST repeat of an identical call gets a nudge
/// carrying the result the model already has; only a further repeat finalizes. Finalizing on the
/// first repeat is what turned the F25 incident terminal — an enrichment run repeated a search and
/// "finished" with raw search results instead of writing the required CSV.
final class AgentRepeatedCallGuardTests: XCTestCase {
    func testSoftWarningEchoesThePreviousResultAndNamesBothWaysForward() {
        let warning = AgentRepeatedCallGuard.softWarning(
            call: ToolCall(name: "host.web.search", argumentsJSON: #"{"query":"stripe"}"#),
            previousResult: ToolResult(ok: true, stdout: "1. Stripe — https://stripe.com")
        )
        XCTAssertTrue(warning.contains("host.web.search"))
        XCTAssertTrue(warning.contains("https://stripe.com"))
        XCTAssertTrue(warning.contains("Do not repeat that call"))
        XCTAssertTrue(warning.contains("give your final answer"))
    }

    func testSoftWarningTruncatesLargeOutputAndHandlesEmpty() {
        let large = String(repeating: "x", count: AgentRepeatedCallGuard.resultEchoLimit + 500)
        let warning = AgentRepeatedCallGuard.softWarning(
            call: ToolCall(name: "host.file.read", argumentsJSON: #"{"path":"a.txt"}"#),
            previousResult: ToolResult(ok: true, stdout: large)
        )
        XCTAssertTrue(warning.contains("[truncated]"))
        XCTAssertLessThan(warning.count, large.count)

        let empty = AgentRepeatedCallGuard.softWarning(
            call: ToolCall(name: "host.file.list", argumentsJSON: "{}"),
            previousResult: ToolResult(ok: true, stdout: "")
        )
        XCTAssertTrue(empty.contains("produced no output"))
    }

    func testStateWarnsOncePerDistinctCall() {
        var state = AgentRunLoopState()
        let call = ToolCall(name: "host.file.list", argumentsJSON: #"{"path":"."}"#)
        let other = ToolCall(name: "host.file.list", argumentsJSON: #"{"path":"src"}"#)
        XCTAssertTrue(state.shouldSoftWarnOnRepeat(of: call))
        XCTAssertFalse(state.shouldSoftWarnOnRepeat(of: call), "a second repeat must finalize")
        XCTAssertTrue(state.shouldSoftWarnOnRepeat(of: other), "a different call gets its own nudge")
    }

    // MARK: - End to end

    private actor ScriptedState {
        var steps: [AgentAction]
        var calls = 0
        init(_ steps: [AgentAction]) { self.steps = steps }
        func next() -> AgentAction {
            calls += 1
            return steps.isEmpty ? .say("out of steps") : steps.removeFirst()
        }
        func callCount() -> Int { calls }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            await state.next()
        }
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("repeat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFirstRepeatIsNudgedAndTheRunRecovers() async throws {
        let root = try makeWorkspace()
        let list = ToolCall(name: "host.file.list", argumentsJSON: #"{"path":"."}"#)
        // list, list (repeat -> nudge, no finalize), then a real answer.
        let state = ScriptedState([.tool(list), .tool(list), .say("The folder is empty.")])
        let runner = AgentRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "What is in this folder?",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        let final = try XCTUnwrap(result.thread.messages.last?.content)
        XCTAssertEqual(final, "The folder is empty.", "the nudged run must reach the model's own answer")
        XCTAssertTrue(result.thread.messages.contains { $0.content.contains("Do not repeat that call") })
        XCTAssertTrue(result.thread.events.contains { ($0.summary ?? "").contains("repeated the same") })
    }

    func testSecondRepeatStillFinalizes() async throws {
        let root = try makeWorkspace()
        let list = ToolCall(name: "host.file.list", argumentsJSON: #"{"path":"."}"#)
        // A model that ignores the nudge and repeats again must still terminate.
        let state = ScriptedState([.tool(list), .tool(list), .tool(list)])
        let runner = AgentRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "What is in this folder?",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertNotNil(result.thread.messages.last?.content)
        XCTAssertFalse(try XCTUnwrap(result.thread.messages.last?.content).isEmpty)
    }
}
