import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceRemoteProjectShellGitIntegrationTests: XCTestCase {
    func testRemoteProjectSubagentRunsShellThroughSSH() async throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-subagent-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let thread = ChatThread(projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "pwd"])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("/subagents inspect remote | Explorer: run pwd on the remote project")
        await model.submitComposer(workspaceRoot: root)

        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, [
            "-T",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=4",
            "-p",
            "2222",
            "--",
            "quill@feather.local",
            "cd '/srv/quill' && pwd"
        ])
        let completedThread = try XCTUnwrap(model.selectedThread)
        let update = try XCTUnwrap(SubagentProgressToolExecutor.latestUpdate(in: completedThread))
        XCTAssertEqual(update.subagents.map(\.status), [.completed])
        XCTAssertTrue(update.subagents.first?.summary?.contains("remote-terminal") == true)
    }

    func testRemoteProjectAgentRunsShellThroughSSH() async throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "pwd"])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Run pwd")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.executionContext?.label, "SSH Remote")
        XCTAssertEqual(card.executionContext?.detail, "feather.local")
        let timelineCard = try XCTUnwrap(model.currentTimelineItems.compactMap(\.toolCard).last)
        XCTAssertEqual(timelineCard.executionContext, card.executionContext)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "remote-terminal\n")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, [
            "-T",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=4",
            "-p",
            "2222",
            "--",
            "quill@feather.local",
            "cd '/srv/quill' && pwd"
        ])
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("remote-terminal") == true)
    }

    func testRemoteProjectAgentRunsReadOnlyGitStatusThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        try "# Test repo\nchanged\n".write(
            to: remoteRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let argumentsFile = root.appendingPathComponent("ssh-agent-git-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitStatus.name,
                argumentsJSON: "{}"
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("git status")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitStatus.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.executionContext?.label, "SSH Remote")
        XCTAssertEqual(card.executionContext?.detail, "feather.local")
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("README.md"), result.stdout)

        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("-p\n2222\n--\nquill@feather.local\n"), arguments)
        XCTAssertTrue(
            arguments.contains("cd '\(remoteRoot.path.replacingOccurrences(of: "'", with: "'\\''"))' && git status --short --branch"),
            arguments
        )
    }

    func testRemoteProjectAgentCommitsThroughSSH() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        try "remote\n".write(
            to: remoteRoot.appendingPathComponent("remote.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try runGit(["add", "remote.txt"], cwd: remoteRoot)
        let argumentsFile = root.appendingPathComponent("ssh-agent-commit-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitCommit.name,
                argumentsJSON: ToolArguments.json(["message": "Add remote file"])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        model.setDraft("Commit staged changes")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitCommit.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(try runGit(["log", "--oneline", "-1"], cwd: remoteRoot).contains("Add remote file"))
        XCTAssertEqual(try runGit(["status", "--short"], cwd: remoteRoot), "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("remote.txt").path))
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("git commit -m 'Add remote file'"), arguments)
    }

    func testRemoteProjectAgentPushesCurrentBranchThroughSSH() async throws {
        let root = try makeTempDirectory()
        let parent = try makeTempDirectory()
        let remoteRoot = parent.appendingPathComponent("repo")
        let bareRemote = parent.appendingPathComponent("origin.git")
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
        try initializeGitRepository(at: remoteRoot)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init --bare '\(bareRemote.path)'", cwd: parent)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git remote add origin '\(bareRemote.path)'", cwd: remoteRoot)).ok)
        try "remote\n".write(
            to: remoteRoot.appendingPathComponent("remote.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try runGit(["add", "remote.txt"], cwd: remoteRoot)
        _ = try runGit(["commit", "-m", "Add remote file"], cwd: remoteRoot)
        let branch = try currentBranchName(in: remoteRoot)
        let argumentsFile = root.appendingPathComponent("ssh-agent-push-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitPush.name,
                argumentsJSON: #"{"remote":"origin","setUpstream":true}"#
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        model.setDraft("Push current branch")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPush.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.ok, result.error ?? "")
        let remoteHead = ShellToolExecutor().run(.init(
            command: "git --git-dir='\(bareRemote.path)' rev-parse \(branch)",
            cwd: parent
        ))
        XCTAssertTrue(remoteHead.ok, "\(remoteHead.error ?? "") \(remoteHead.stderr)")
        XCTAssertFalse(remoteHead.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("git push -u 'origin' \"$branch\""), arguments)
    }

    func testRemoteProjectWorkspaceCommandsRunReadOnlyGitThroughSSH() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        try "# Test repo\nchanged\n".write(
            to: remoteRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let argumentsFile = root.appendingPathComponent("ssh-command-git-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        XCTAssertTrue(model.runWorkspaceCommand("git-status", workspaceRoot: root))
        var card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitStatus.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        var result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.stdout.contains("README.md"), result.stdout)

        XCTAssertTrue(model.runWorkspaceCommand("git-diff", workspaceRoot: root))
        card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitDiff.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.stdout.contains("+changed"), result.stdout)

        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("git diff"), arguments)
    }

    func testRemoteProjectShellCWDNormalizesRelativePaths() async throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-agent-cwd-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill"
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "pwd",
                    "cwd": "logs/../releases/./current"
                ])
            ))),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.setDraft("Run pwd in releases current")
        await model.submitComposer(workspaceRoot: root)

        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments.last, "cd '/srv/quill/releases/current' && pwd")
    }
}
