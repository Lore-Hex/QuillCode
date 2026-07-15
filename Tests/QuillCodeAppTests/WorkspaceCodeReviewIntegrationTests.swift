import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceCodeReviewIntegrationTests: XCTestCase {
    func testReviewRunsDedicatedInvestigationAndMergesOnlyStructuredReport() async throws {
        let workspaceRoot = try makeTempGitRepoWithInitialCommit()
        let readme = workspaceRoot.appendingPathComponent("README.md")
        try "# Updated\n".write(to: readme, atomically: true, encoding: .utf8)
        let project = ProjectRef(name: "Review fixture", path: workspaceRoot.path)
        let thread = ChatThread(
            title: "Review task",
            projectID: project.id,
            model: "trustedrouter/fast"
        )
        let reviewer = CodeReviewSequenceLLM(actions: [
            .tool(ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}")),
            .tool(ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")),
            .tool(ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: #"{"staged":true}"#)),
            .tool(ToolCall(name: ToolDefinition.fileRead.name, argumentsJSON: #"{"path":"README.md"}"#)),
            .tool(ToolCall(
                name: WorkspaceCodeReviewSubmitTool.name,
                argumentsJSON: #"{"summary":"One correctness issue.","findings":[{"priority":"P2","title":"Keep the original heading","body":"The replacement removes the fixture's expected heading.","path":"README.md","line":1}]}"#
            )),
            .say("Review complete.")
        ])
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            runner: AgentRunner(llm: reviewer, maxToolSteps: 12)
        )
        var sawImmediateUserTurn = false

        let succeeded = await model.runCodeReview(
            WorkspaceCodeReviewRequest(scope: .uncommitted),
            workspaceRoot: workspaceRoot,
            onProgressUpdated: {
                sawImmediateUserTurn = sawImmediateUserTurn
                    || model.selectedThread?.messages.first?.content == "Review all uncommitted changes"
            }
        )

        XCTAssertTrue(succeeded)
        XCTAssertTrue(sawImmediateUserTurn)
        XCTAssertNil(model.codeReviewRequest)
        XCTAssertEqual(model.selectedThread?.model, "trustedrouter/fast")
        XCTAssertEqual(model.selectedThread?.messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("[P2] Keep the original heading") == true)
        XCTAssertEqual(model.selectedThread?.events.filter { $0.kind == .reviewComment }.count, 1)
        XCTAssertEqual(model.currentToolCards.map(\.title), [ToolDefinition.gitDiff.name])
        XCTAssertEqual(try String(contentsOf: readme, encoding: .utf8), "# Updated\n")

        let review = model.surface().review
        XCTAssertEqual(review.codeReviewFindingCount, 1)
        XCTAssertEqual(review.files.map(\.path), ["README.md"])
        XCTAssertTrue(review.files.flatMap(\.hunkItems).flatMap(\.lines).flatMap(\.comments).contains {
            $0.title == "Keep the original heading"
        })
    }

    func testReviewFailsVisiblyWhenReviewerOmitsStructuredReport() async throws {
        let workspaceRoot = try makeTempGitRepoWithInitialCommit()
        let project = ProjectRef(name: "Review fixture", path: workspaceRoot.path)
        let thread = ChatThread(title: "Review task", projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            runner: AgentRunner(llm: CodeReviewSequenceLLM(actions: [.say("Looks clean.")]))
        )

        let succeeded = await model.runCodeReview(
            WorkspaceCodeReviewRequest(),
            workspaceRoot: workspaceRoot
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.selectedThread?.messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("required structured report") == true)
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }

    func testReviewRejectsNonGitWorkspaceBeforeCreatingTranscriptState() async throws {
        let workspaceRoot = try makeTempDirectory()
        let project = ProjectRef(name: "Plain folder", path: workspaceRoot.path)
        let thread = ChatThread(title: "Review task", projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            runner: AgentRunner(llm: CodeReviewSequenceLLM(actions: [.say("Should not run.")]))
        )

        let succeeded = await model.runCodeReview(
            WorkspaceCodeReviewRequest(),
            workspaceRoot: workspaceRoot
        )

        XCTAssertFalse(succeeded)
        XCTAssertTrue(model.selectedThread?.messages.isEmpty == true)
        XCTAssertTrue(model.selectedThread?.events.isEmpty == true)
        XCTAssertEqual(model.root.threads.count, 1)
        XCTAssertTrue(model.lastError?.contains("Git repository") == true)
        XCTAssertEqual(model.root.topBar.agentStatus, TopBarAgentStatusLabel.failed)
    }

    func testDetachedReviewWithoutExistingThreadCreatesExactlyOneReviewTask() async throws {
        let workspaceRoot = try makeTempGitRepoWithInitialCommit()
        let project = ProjectRef(name: "Review fixture", path: workspaceRoot.path)
        let reviewer = CodeReviewSequenceLLM(actions: [
            .tool(ToolCall(
                name: WorkspaceCodeReviewSubmitTool.name,
                argumentsJSON: #"{"summary":"No findings.","findings":[]}"#
            )),
            .say("Review complete.")
        ])
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id
            ),
            runner: AgentRunner(llm: reviewer)
        )

        let succeeded = await model.runCodeReview(
            WorkspaceCodeReviewRequest(delivery: .detached),
            workspaceRoot: workspaceRoot
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.root.threads.count, 1)
        XCTAssertEqual(model.selectedThread?.title, "Code review: Uncommitted changes")
        XCTAssertEqual(model.selectedThread?.messages.map(\.role), [.user, .assistant])
    }

    func testCancellingReviewLeavesVisibleStoppedStateAndFinishesRun() async throws {
        let workspaceRoot = try makeTempGitRepoWithInitialCommit()
        let project = ProjectRef(name: "Review fixture", path: workspaceRoot.path)
        let thread = ChatThread(title: "Review task", projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            runner: AgentRunner(llm: SuspendedCodeReviewLLM())
        )
        let task = Task {
            await model.runCodeReview(
                WorkspaceCodeReviewRequest(),
                workspaceRoot: workspaceRoot
            )
        }
        while !model.isAgentRunActive(for: thread.id) {
            await Task.yield()
        }

        task.cancel()
        let succeeded = await task.value

        XCTAssertFalse(succeeded)
        XCTAssertFalse(model.isAgentRunActive(for: thread.id))
        XCTAssertEqual(model.selectedThread?.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Code review stopped.")
        XCTAssertEqual(model.root.topBar.agentStatus, TopBarAgentStatusLabel.stopped)
    }

    func testRemoteReviewPreflightAndInvestigationUseSSHWorkspace() async throws {
        let workspaceRoot = try makeTempGitRepoWithInitialCommit()
        let supportRoot = try makeTempDirectory()
        let argumentsFile = supportRoot.appendingPathComponent("ssh-arguments.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: supportRoot, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: workspaceRoot.path,
            host: "review.example",
            user: "quill"
        )
        let project = ProjectRef(name: "Remote review", path: connection.path, connection: connection)
        let thread = ChatThread(title: "Remote task", projectID: project.id)
        let reviewer = CodeReviewSequenceLLM(actions: [
            .tool(ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}")),
            .tool(ToolCall(
                name: WorkspaceCodeReviewSubmitTool.name,
                argumentsJSON: #"{"summary":"Remote repository is clean.","findings":[]}"#
            )),
            .say("Review complete.")
        ])
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            runner: AgentRunner(llm: reviewer),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        let succeeded = await model.runCodeReview(
            WorkspaceCodeReviewRequest(),
            workspaceRoot: workspaceRoot
        )

        XCTAssertTrue(succeeded, model.lastError ?? "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: argumentsFile.path))
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Remote repository is clean") == true)
        XCTAssertEqual(model.selectedThread?.messages.filter { $0.role == .tool }.count, 0)
    }
}

private actor CodeReviewSequenceLLM: LLMClient {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) -> AgentAction {
        guard !actions.isEmpty else { return .say("Done.") }
        return actions.removeFirst()
    }
}

private struct SuspendedCodeReviewLLM: LLMClient {
    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return .say("Unexpected completion.")
    }
}
