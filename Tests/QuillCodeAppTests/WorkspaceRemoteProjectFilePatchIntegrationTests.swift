import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceRemoteProjectFilePatchIntegrationTests: XCTestCase {
    func testRemoteProjectMockFileRequestUsesSSHFileWrite() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-agent-file-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill"
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.fileWrite.name)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))
        XCTAssertEqual(
            try String(contentsOf: remoteRoot.appendingPathComponent("hello.txt"), encoding: .utf8),
            "hello world\n"
        )
        XCTAssertEqual(result.artifacts.first, "ssh://quill@feather.local\(remoteRoot.path)/hello.txt")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("quill@feather.local"), arguments)
        XCTAssertTrue(arguments.contains("cd '\(remoteRoot.path)' && mkdir -p -- '.'"), arguments)
        XCTAssertTrue(arguments.contains("| base64 --decode > 'hello.txt'"), arguments)
    }

    func testRemoteProjectAgentReadsRemoteFilesThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempDirectory()
        try FileManager.default.createDirectory(
            at: remoteRoot.appendingPathComponent("docs"),
            withIntermediateDirectories: true
        )
        try "remote notes\n".write(
            to: remoteRoot.appendingPathComponent("docs/notes.md"),
            atomically: true,
            encoding: .utf8
        )
        let argumentsFile = root.appendingPathComponent("ssh-agent-file-read-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": "docs/notes.md"])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Read docs/notes.md")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.fileRead.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "remote notes\n")
        XCTAssertEqual(result.artifacts.first, "ssh://quill@feather.local\(remoteRoot.path)/docs/notes.md")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("cat -- 'docs/notes.md'"), arguments)
    }

    func testRemoteProjectRejectsUnsafeRemoteFilePath() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-agent-unsafe-file-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "../escape.txt",
                    "content": "should not be written\n"
                ])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Write outside remote root")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("outside the workspace") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: remoteRoot.deletingLastPathComponent().appendingPathComponent("escape.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: argumentsFile.path))
    }

    func testRemoteProjectAppliesPatchThroughSSHAndRefreshesRemoteDiff() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        try "old\n".write(
            to: remoteRoot.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try runGit(["add", "hello.txt"], cwd: remoteRoot)
        _ = try runGit(["commit", "-m", "add hello"], cwd: remoteRoot)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let argumentsFile = root.appendingPathComponent("ssh-agent-patch-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.applyPatch.name,
                argumentsJSON: ToolArguments.json(["patch": patch])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Apply this patch")
        await model.submitComposer(workspaceRoot: root)

        let cards = model.currentToolCards
        XCTAssertEqual(cards.map(\.title), [ToolDefinition.applyPatch.name, ToolDefinition.gitDiff.name])
        XCTAssertEqual(cards.map(\.executionContext?.kind), [.sshRemote, .sshRemote])
        let patchResult = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(cards.first?.outputJSON))
        XCTAssertTrue(patchResult.ok, patchResult.error ?? "")
        XCTAssertEqual(patchResult.stdout, "Patch applied.\n")
        XCTAssertEqual(
            try String(contentsOf: remoteRoot.appendingPathComponent("hello.txt"), encoding: .utf8),
            "new\n"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))

        let diffResult = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(cards.last?.outputJSON))
        XCTAssertTrue(diffResult.ok, diffResult.error ?? "")
        XCTAssertTrue(diffResult.stdout.contains("+new"), diffResult.stdout)
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("git diff"), arguments)
    }

    func testRemoteProjectRejectsUnsafeRemotePatchBeforeSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let argumentsFile = root.appendingPathComponent("ssh-agent-unsafe-patch-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let patch = """
        diff --git a/../escape.txt b/../escape.txt
        --- a/../escape.txt
        +++ b/../escape.txt
        @@ -0,0 +1 @@
        +bad
        """
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.applyPatch.name,
                argumentsJSON: ToolArguments.json(["patch": patch])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Apply unsafe patch")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.applyPatch.name)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("unsafe path") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: argumentsFile.path))
    }
}
