import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceRemoteProjectWorktreeIntegrationTests: XCTestCase {
    func testRemoteProjectAgentCreatesWorktreeThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let worktreeName = "remote-agent-\(UUID().uuidString)"
        let branch = "remote-agent-\(UUID().uuidString.prefix(8))"
        let worktree = remoteRoot.deletingLastPathComponent()
            .appendingPathComponent(worktreeName)
            .standardizedFileURL
        let argumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitWorktreeCreate.name,
                argumentsJSON: ToolArguments.json([
                    "path": worktreeName,
                    "branch": String(branch)
                ])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Create a worktree")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitWorktreeCreate.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? result.stderr)
        XCTAssertEqual(result.artifacts, ["ssh://quill@feather.local\(worktree.path)"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))

        let sshArguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(sshArguments.contains("'git' 'worktree' 'add' '-b' '\(branch)' '\(worktree.path)'"), sshArguments)
    }

    func testRemoteProjectRejectsUnsafeWorktreePathBeforeSSH() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        let result = model.runToolCall(
            ToolCall(
                name: ToolDefinition.gitWorktreeCreate.name,
                argumentsJSON: ToolArguments.json(["path": "../../etc"])
            ),
            workspaceRoot: root
        )

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("outside the workspace") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: argumentsFile.path))
    }
}
