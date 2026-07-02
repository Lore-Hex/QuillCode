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

    func testPromptOffersOptionalDelegationViaTheParsedMarker() {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(
            objective: "ship release",
            job: WorkspaceSubagentJob(name: "Builder", role: "build")
        )

        // The marker the prompt advertises must be exactly the one the parser recognizes, and the
        // guidance must stay opt-in ("only if") so workers do not over-delegate.
        XCTAssertTrue(prompt.contains(WorkspaceSubagentSpawnDirectiveParser.openMarker))
        XCTAssertTrue(prompt.contains("only if"))
        XCTAssertTrue(prompt.contains("sparingly"))
        // The advertised marker is actually parseable into a child request with the expected name/role
        // (not just a non-zero count), so prompt wording and parser semantics cannot drift apart.
        let parsed = WorkspaceSubagentSpawnDirectiveParser.parse("[[DELEGATE: short name | what that subagent should do]]")
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
                priorResults: [WorkspaceSubagentPriorResult(name: "Builder", summary: "compiled the app cleanly")]
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

    // MARK: - Prompt caching opt-out (one-shot aux class)

    /// The opt-out the WorkspaceModel applies to the subagent worker: it disables caching on a
    /// caching-capable client (threading through the production retry-wrapped TrustedRouter shape)
    /// and returns a non-caching client (the mock) unchanged. A subagent worker issues a single
    /// tool-free nextAction on a FRESH, unique-prompt thread that is never re-sent, so a
    /// breakpoint there could only ever be a cache write with no read — this opt-out prevents it.
    /// Fails on revert of disablingPromptCachingIfSupported / its conformances.
    func testDisablingPromptCachingIfSupportedActsOnCachingClientsOnly() throws {
        let retryWrapped = RetryingLLMClient(base: TrustedRouterLLMClient(promptCachingPolicy: .automatic))
        let disabled = disablingPromptCachingIfSupported(retryWrapped)
        let disabledClient = try XCTUnwrap(disabled as? RetryingLLMClient<TrustedRouterLLMClient>)
        XCTAssertEqual(disabledClient.base.promptCachingPolicy, .disabled)

        // A client that does not support the control is returned unchanged (not wrapped/altered).
        let mock = SubagentStubSayLLMClient(text: "ok")
        XCTAssertTrue(disablingPromptCachingIfSupported(mock) is SubagentStubSayLLMClient)
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
