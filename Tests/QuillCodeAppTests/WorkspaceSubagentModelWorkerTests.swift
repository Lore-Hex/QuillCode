import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSubagentModelWorkerTests: XCTestCase {
    func testRunReturnsCollapsedModelSayText() async throws {
        let worker = LLMWorkspaceSubagentWorker(
            llm: SubagentStubSayLLMClient(text: "  Inspected the parser\n  and found two edge cases.  ")
        )

        let summary = try await worker.run(
            WorkspaceSubagentJob(name: "Explorer", role: "inspect code", objective: "validate release")
        )

        XCTAssertEqual(summary, "Inspected the parser and found two edge cases.")
    }

    func testRunFallsBackToRoleForEmptySay() async throws {
        let worker = LLMWorkspaceSubagentWorker(llm: SubagentStubSayLLMClient(text: "   \n  "))

        let summary = try await worker.run(
            WorkspaceSubagentJob(name: "Verifier", role: "run focused tests", objective: "ship the release")
        )

        XCTAssertEqual(summary, "Completed run focused tests")
    }

    func testRunSummarizesToolAction() async throws {
        let worker = LLMWorkspaceSubagentWorker(llm: SubagentStubToolLLMClient(toolName: "host.shell.run"))

        let summary = try await worker.run(
            WorkspaceSubagentJob(name: "Runner", role: "execute checks", objective: "build and verify")
        )

        XCTAssertEqual(summary, "Proposed host.shell.run")
    }

    func testPromptIncludesObjectiveRoleAndSayContract() {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(
            objective: "validate release",
            job: WorkspaceSubagentJob(name: "Explorer", role: "inspect code")
        )

        XCTAssertTrue(prompt.contains("validate release"))
        XCTAssertTrue(prompt.contains("inspect code"))
        XCTAssertTrue(prompt.contains("Explorer"))
        XCTAssertTrue(prompt.contains(#"{"type":"say","text":"..."}"#))
    }

    func testRunPropagatesClientErrors() async {
        let worker = LLMWorkspaceSubagentWorker(llm: SubagentStubThrowingLLMClient())

        do {
            _ = try await worker.run(
                WorkspaceSubagentJob(name: "Explorer", role: "inspect code", objective: "validate release")
            )
            XCTFail("Expected the worker to propagate the client error")
        } catch {
            // Expected: scheduler turns a thrown worker error into a failed subagent.
        }
    }
}

private struct SubagentStubSayLLMClient: LLMClient {
    var text: String

    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        .say(text)
    }
}

private struct SubagentStubToolLLMClient: LLMClient {
    var toolName: String

    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        .tool(ToolCall(name: toolName, argumentsJSON: "{}"))
    }
}

private struct SubagentStubThrowingLLMClient: LLMClient {
    struct Failure: Error {}

    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        throw Failure()
    }
}
