import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceRemoteProjectPullRequestIntegrationTests: XCTestCase {
    func testRemoteProjectAgentCreatesPullRequestThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let sshArgumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitPullRequestCreate.name,
                argumentsJSON: """
                {
                    "title": "Add remote PR",
                    "body": "Remote body",
                    "base": "main",
                    "head": "feature/remote",
                    "draft": true
                }
                """
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Create a PR")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestCreate.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/456"])

        let ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(ghArguments, [
            "pr",
            "create",
            "--title",
            "Add remote PR",
            "--body",
            "Remote body",
            "--base",
            "main",
            "--head",
            "feature/remote",
            "--draft"
        ])
    }

    func testRemoteProjectAgentCommentsOnPullRequestThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let sshArgumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitPullRequestComment.name,
                argumentsJSON: #"{"selector":"456","body":"Ready for review."}"#
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Comment on PR 456 saying Ready for review.")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestComment.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/456"])

        let ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(ghArguments, ["pr", "comment", "456", "--body", "Ready for review."])
    }

    func testRemoteProjectAgentReviewsPullRequestThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let sshArgumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitPullRequestReview.name,
                argumentsJSON: #"{"selector":"456","action":"request_changes","body":"Please add tests."}"#
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Request changes on PR 456 saying Please add tests.")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestReview.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/456"])

        let ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(ghArguments, [
            "pr",
            "review",
            "456",
            "--request-changes",
            "--body",
            "Please add tests."
        ])
    }

    func testRemoteProjectAgentMergesPullRequestThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let sshArgumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitPullRequestMerge.name,
                argumentsJSON: #"{"selector":"456","method":"squash","auto":true,"deleteBranch":true}"#
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Auto merge PR 456 and delete branch.")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestMerge.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/456"])

        let ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(ghArguments, [
            "pr",
            "merge",
            "456",
            "--squash",
            "--auto",
            "--delete-branch"
        ])
    }

    func testRemoteProjectAgentChecksOutPullRequestThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let sshArgumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitPullRequestCheckout.name,
                argumentsJSON: #"{"selector":"456","branch":"review/pr-456"}"#
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Checkout PR 456.")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestCheckout.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/456"])

        let ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(ghArguments, [
            "pr",
            "checkout",
            "456",
            "--branch",
            "review/pr-456"
        ])
    }

    func testRemoteProjectAgentRequestsPullRequestReviewersThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let sshArgumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitPullRequestReviewers.name,
                argumentsJSON: #"{"selector":"456","add":["alice","myorg/team-name"],"remove":"bob"}"#
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Request reviewers on PR 456.")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestReviewers.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/456"])

        let ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(ghArguments, [
            "pr",
            "edit",
            "456",
            "--add-reviewer",
            "alice,myorg/team-name",
            "--remove-reviewer",
            "bob"
        ])
    }

    func testRemoteProjectAgentLabelsPullRequestThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let sshArgumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitPullRequestLabels.name,
                argumentsJSON: #"{"selector":"456","add":["merge-train","needs review"],"remove":"blocked"}"#
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Label PR 456 merge-train.")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/456"])

        let ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(ghArguments, [
            "pr",
            "edit",
            "456",
            "--add-label",
            "merge-train,needs review",
            "--remove-label",
            "blocked"
        ])
    }
}
