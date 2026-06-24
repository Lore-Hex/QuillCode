import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceRemoteProjectIntegrationTests: XCTestCase {
    func testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/ssh quill@feather.local:/srv/quill")
        await model.submitComposer(workspaceRoot: URL(fileURLWithPath: "/tmp/local"))

        let project = try XCTUnwrap(model.selectedProject)
        XCTAssertEqual(project.name, "feather.local · quill")
        XCTAssertEqual(project.connection, .ssh(path: "/srv/quill", host: "feather.local", user: "quill"))
        XCTAssertEqual(project.displayPath, "ssh://quill@feather.local/srv/quill")
        XCTAssertTrue(project.isRemote)
        XCTAssertNil(model.activeWorkspaceRoot)
        XCTAssertEqual(model.terminal.currentDirectoryPath, "ssh://quill@feather.local/srv/quill")

        let surface = model.surface()
        XCTAssertEqual(surface.terminal.cwdLabel, "ssh://quill@feather.local/srv/quill")
        XCTAssertEqual(surface.projects.items.first?.connectionKindLabel, "SSH Remote")
        XCTAssertEqual(surface.projects.items.first?.actions.first { $0.kind == .refreshContext }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-view" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checks" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-diff" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checkout" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-reviewers" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-comment" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-labels" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-merge" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-list" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-remove" }?.isEnabled, true)
        XCTAssertEqual(model.selectedThread?.messages.last?.content.contains("Added SSH Remote"), true)
        XCTAssertEqual(model.selectedThread?.messages.last?.content.contains("PR checkout/reviewers/labels/merge"), true)
    }

    func testRefreshProjectContextLoadsSSHRemoteInstructionsAndMemories() throws {
        let root = try makeTempDirectory()
        let remoteRoot = root.appendingPathComponent("remote repo")
        try FileManager.default.createDirectory(
            at: remoteRoot.appendingPathComponent(".quillcode/memories"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: remoteRoot.appendingPathComponent("Sources/Feature"),
            withIntermediateDirectories: true
        )
        try "Root agent rules".write(
            to: remoteRoot.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Remote project rules".write(
            to: remoteRoot.appendingPathComponent(".quillcode/rules.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Feature-scoped rules".write(
            to: remoteRoot.appendingPathComponent("Sources/Feature/AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Prefer short final answers.".write(
            to: remoteRoot.appendingPathComponent(".quillcode/memories/team-note.md"),
            atomically: true,
            encoding: .utf8
        )

        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
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
        _ = model.newChat(projectID: project.id)

        XCTAssertTrue(model.refreshProjectContext(project.id), model.lastError ?? "")

        let refreshedProject = try XCTUnwrap(model.root.projects.first)
        XCTAssertEqual(
            refreshedProject.instructions.map(\.path),
            ["AGENTS.md", ".quillcode/rules.md", "Sources/Feature/AGENTS.md"]
        )
        XCTAssertEqual(refreshedProject.instructions.map(\.content), [
            "Root agent rules",
            "Remote project rules",
            "Feature-scoped rules"
        ])
        XCTAssertEqual(refreshedProject.memories.map(\.relativePath), [".quillcode/memories/team-note.md"])
        XCTAssertEqual(refreshedProject.memories.first?.title, "Team Note")
        XCTAssertEqual(refreshedProject.memories.first?.content, "Prefer short final answers.")
        XCTAssertEqual(model.selectedThread?.instructions.map(\.path), refreshedProject.instructions.map(\.path))
        XCTAssertEqual(model.selectedThread?.memories.map(\.relativePath), refreshedProject.memories.map(\.relativePath))
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Refreshed project context")

        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("cd '\(remoteRoot.path.replacingOccurrences(of: "'", with: "'\\''"))' &&"))
        XCTAssertTrue(arguments.contains("QUILLCODE_CONTEXT_"))
    }

    func testSlashSSHRejectsMalformedAddress() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/ssh feather.local relative/path")
        await model.submitComposer(workspaceRoot: URL(fileURLWithPath: "/tmp/local"))

        XCTAssertTrue(model.root.projects.isEmpty)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Use SSH format user@host:/path or ssh://user@host/path."
        )
    }

    func testRemoteProjectAgentOffersOnlyRemoteSafeBaseTools() async throws {
        let root = try makeTempDirectory()
        let connection = ProjectConnection.ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let recorder = ToolDefinitionRecorder()
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: RecordingLLMClient(recorder: recorder))
        )

        model.setDraft("What can you do here?")
        await model.submitComposer(workspaceRoot: root)

        let toolNames = Set(recorder.tools.map(\.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.shellRun.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.fileRead.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.fileWrite.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.applyPatch.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitStatus.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitDiff.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitStage.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitRestore.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitStageHunk.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitRestoreHunk.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitCommit.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPush.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestCreate.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestView.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestChecks.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestCheckout.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestReviewers.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestLabels.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestComment.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestReview.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestMerge.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitWorktreeList.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitWorktreeCreate.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitWorktreeRemove.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.planUpdate.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.browserInspect.name))
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
        XCTAssertTrue(arguments.contains("-p\n2222\nquill@feather.local\n"), arguments)
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
