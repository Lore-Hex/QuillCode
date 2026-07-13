import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceSubagentSpawnDirectiveParserTests: XCTestCase {
    func testParsesBracketedDelegateMarkers() {
        let text = "Inspected the build. [[DELEGATE: Compile | compile the project]] and [[DELEGATE: Test | run the tests]]."
        let requests = WorkspaceSubagentSpawnDirectiveParser.parse(text)
        XCTAssertEqual(requests.map(\.name), ["Compile", "Test"])
        XCTAssertEqual(requests.map(\.role), ["compile the project", "run the tests"])
    }

    func testRoleMayContainPipesViaFirstPipeSplit() {
        // The role is free-form prose that often contains pipes (shell pipes, alternation). Splitting
        // on the FIRST pipe keeps the whole role instead of dropping the directive.
        let requests = WorkspaceSubagentSpawnDirectiveParser.parse("[[DELEGATE: Build | compile | link the app]]")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.name, "Build")
        XCTAssertEqual(requests.first?.role, "compile | link the app")
    }

    func testIgnoresMalformedAndEmptyDirectives() {
        let text = """
        [[DELEGATE: no pipe here]]
        [[DELEGATE:  | empty name]]
        [[DELEGATE: name only | ]]
        [[NOTADIRECTIVE: x | y]]
        plain summary text
        """
        XCTAssertEqual(WorkspaceSubagentSpawnDirectiveParser.parse(text), [])
    }

    func testCapsChildrenPerWorker() {
        let text = (1...10).map { "[[DELEGATE: W\($0) | role \($0)]]" }.joined(separator: " ")
        XCTAssertEqual(WorkspaceSubagentSpawnDirectiveParser.parse(text).count, 3)
    }

    func testDeduplicatesByNameCaseInsensitively() {
        let text = "[[DELEGATE: Dup | first]] [[DELEGATE: dup | second]]"
        XCTAssertEqual(WorkspaceSubagentSpawnDirectiveParser.parse(text).map(\.name), ["Dup"])
    }

    func testBoundsNameAndRoleLengthAndStripsPathSeparators() {
        let longName = String(repeating: "x", count: 200)
        let longRole = String(repeating: "y", count: 300)
        let requests = WorkspaceSubagentSpawnDirectiveParser.parse("[[DELEGATE: a/b#c \(longName) | \(longRole)]]")
        XCTAssertEqual(requests.count, 1)
        XCTAssertLessThanOrEqual(requests[0].name.count, 72)
        XCTAssertLessThanOrEqual(requests[0].role.count, 160)
        XCTAssertFalse(requests[0].name.contains("/"), "path separator must be stripped from child names")
        XCTAssertFalse(requests[0].name.contains("#"), "dedup-suffix marker must be stripped from child names")
    }

    func testNoMarkersReturnsEmpty() {
        XCTAssertEqual(WorkspaceSubagentSpawnDirectiveParser.parse("A normal result with no delegation."), [])
    }

    /// The directive must survive the agent worker's whitespace collapse — that is the
    /// whole reason the marker is bracketed rather than line-based. Drive the real worker with a stub
    /// client and confirm the collapsed result still parses to the delegated child.
    func testDirectiveSurvivesTheModelWorkerWhitespaceCollapse() async throws {
        let llm = StubDelegatingLLMClient(reply: "Did the analysis.\n\n[[DELEGATE: Compile | compile the project]]")
        let root = try makeQuillCodeTestDirectory()
        let factory = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(llm: llm),
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
        let worker = AgentWorkspaceSubagentWorker(
            sessionFactory: factory,
            parentThread: ChatThread()
        )
        let summary = try await worker.run(WorkspaceSubagentJob(name: "Root", role: "plan"))

        // Whitespace is collapsed (no newline), but the bracketed directive is intact.
        XCTAssertFalse(summary.contains("\n"))
        let requests = WorkspaceSubagentSpawnDirectiveParser.parse(summary)
        XCTAssertEqual(requests.map(\.name), ["Compile"])
        XCTAssertEqual(requests.map(\.role), ["compile the project"])
    }

    /// End-to-end through the real scheduler: a root worker that emits a directive spawns and runs the
    /// delegated child when the parser is wired in as the scheduler's `spawn` closure.
    func testWorkerDelegatesThroughTheSchedulerViaTheParser() async {
        let scheduler = WorkspaceSubagentScheduler { job in
            job.depth == 0 ? "Planned. [[DELEGATE: Compile | compile it]]" : "did \(job.role)"
        }
        let request = WorkspaceSubagentRunRequest(objective: "build", workers: [.init(name: "Root", role: "plan")])

        let result = await scheduler.run(request: request, spawn: { _, summary in
            WorkspaceSubagentSpawnDirectiveParser.parse(summary)
        })

        let names = result.update.subagents.map(\.name)
        XCTAssertTrue(names.contains("Root/Compile"), "the delegated child should be scheduled and run")
        XCTAssertEqual(result.update.subagents.first { $0.name == "Root/Compile" }?.summary, "did compile it")
        XCTAssertTrue(result.update.subagents.allSatisfy { $0.status == SubagentStatus.completed })
    }
}

/// Minimal LLMClient that always replies with a fixed `.say` text, for exercising the model worker's
/// result handling deterministically.
private struct StubDelegatingLLMClient: LLMClient {
    let reply: String
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .say(reply)
    }
}
