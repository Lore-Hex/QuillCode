import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceRemoteProjectToolExecutorTests: XCTestCase {
    func testToolDefinitionsExposeRemoteSafeWorkspaceTools() {
        let names = Set(WorkspaceRemoteProjectToolExecutor.toolDefinitions.map(\.name))

        XCTAssertTrue(names.contains(ToolDefinition.shellRun.name))
        XCTAssertTrue(names.contains(ToolDefinition.fileRead.name))
        XCTAssertTrue(names.contains(ToolDefinition.fileWrite.name))
        XCTAssertTrue(names.contains(ToolDefinition.applyPatch.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitStatus.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitPullRequestCreate.name))
        XCTAssertFalse(names.contains(ToolDefinition.browserInspect.name))
        XCTAssertFalse(names.contains(ToolDefinition.planUpdate.name))
    }

    func testExecutionOverrideRequiresRemoteProject() {
        let local = ProjectRef(name: "Local", path: "/tmp/quillcode")

        XCTAssertNil(WorkspaceRemoteProjectToolExecutor.executionOverride(
            project: local,
            executor: SSHRemoteShellExecutor()
        ))
        XCTAssertNil(WorkspaceRemoteProjectToolExecutor.executionOverride(
            project: nil,
            executor: SSHRemoteShellExecutor()
        ))
    }

    func testRunsRemoteShellThroughSSH() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let project = remoteProject(path: "/srv/quill repo")

        let result = WorkspaceRemoteProjectToolExecutor.execute(
            ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "pwd"])
            ),
            project: project,
            executor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path, connectTimeoutSeconds: 4)
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "remote-ok\n")
        let arguments = try recordedArguments(from: argumentsFile)
        XCTAssertEqual(arguments, [
            "-T",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=4",
            "-p",
            "2222",
            "quill@feather.local",
            "cd '/srv/quill repo' && pwd"
        ])
    }

    func testRemoteFileWriteAddsRemoteArtifact() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let project = remoteProject(path: "/srv/quill")

        let result = WorkspaceRemoteProjectToolExecutor.execute(
            ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "notes/hello.txt",
                    "content": "hello world\n"
                ])
            ),
            project: project,
            executor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.artifacts, ["ssh://quill@feather.local:2222/srv/quill/notes/hello.txt"])
        let command = try recordedArguments(from: argumentsFile).last ?? ""
        XCTAssertTrue(command.contains("mkdir -p -- 'notes'"), command)
        XCTAssertTrue(command.contains("base64 --decode > 'notes/hello.txt'"), command)
    }

    func testRemoteGitPlannerBuildsPullRequestCreateRequest() throws {
        let request = try WorkspaceRemoteGitToolRequestPlanner.request(
            for: ToolCall(
                name: ToolDefinition.gitPullRequestCreate.name,
                argumentsJSON: ToolArguments.json([
                    "title": "Ship it",
                    "body": "Ready for review",
                    "base": "main",
                    "head": "feature/quill",
                    "draft": true
                ])
            ),
            connection: remoteProject(path: "/srv/quill").connection
        )

        XCTAssertEqual(
            request.command,
            "'gh' 'pr' 'create' '--title' 'Ship it' '--body' 'Ready for review' '--base' 'main' '--head' 'feature/quill' '--draft'"
        )
        XCTAssertEqual(request.artifacts, [])
        XCTAssertTrue(request.extractsPullRequestURLs)
    }

    func testRemoteGitPlannerBuildsWorktreeCreateRequestWithArtifact() throws {
        let request = try WorkspaceRemoteGitToolRequestPlanner.request(
            for: ToolCall(
                name: ToolDefinition.gitWorktreeCreate.name,
                argumentsJSON: ToolArguments.json([
                    "path": "quill-next",
                    "branch": "codex/next",
                    "base": "origin/main"
                ])
            ),
            connection: remoteProject(path: "/srv/quill").connection
        )

        XCTAssertEqual(
            request.command,
            "'git' 'worktree' 'add' '-b' 'codex/next' '/srv/quill-next' 'origin/main'"
        )
        XCTAssertEqual(request.artifacts, ["ssh://quill@feather.local:2222/srv/quill-next"])
        XCTAssertFalse(request.extractsPullRequestURLs)
    }

    func testRemoteGitPlannerRejectsWorktreeOutsideRemoteWorkspaceParent() {
        XCTAssertThrowsError(
            try WorkspaceRemoteGitToolRequestPlanner.request(
                for: ToolCall(
                    name: ToolDefinition.gitWorktreeCreate.name,
                    argumentsJSON: ToolArguments.json(["path": "../escape"])
                ),
                connection: remoteProject(path: "/srv/quill").connection
            )
        )
    }

    func testUnsupportedRemoteToolReturnsClearError() {
        let result = WorkspaceRemoteProjectToolExecutor.execute(
            ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
            project: remoteProject(path: "/srv/quill"),
            executor: SSHRemoteShellExecutor()
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Tool is not available for SSH Remote projects: \(ToolDefinition.browserInspect.name)"
        )
    }

    private func remoteProject(path: String) -> ProjectRef {
        let connection = ProjectConnection.ssh(
            path: path,
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        return ProjectRef(name: "Feather", path: connection.path, connection: connection)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFakeSSH(in root: URL, argumentsFile: URL) throws -> URL {
        let fakeSSH = root.appendingPathComponent("ssh")
        let script = """
        #!/bin/sh
        : > "\(argumentsFile.path)"
        for arg in "$@"; do
          printf '%s\\n' "$arg" >> "\(argumentsFile.path)"
        done
        printf 'remote-ok\\n'
        """
        try script.write(to: fakeSSH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)
        return fakeSSH
    }

    private func recordedArguments(from file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }
}
