import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

private struct FakeBrowserPageFetcher: BrowserPageFetching {
    var result: Result<BrowserFetchedPage, BrowserPageFetchFailure>

    func fetchHTML(from url: URL) async throws -> BrowserFetchedPage {
        try result.get()
    }
}

@MainActor
final class WorkspaceModelTests: XCTestCase {
    func testNewChatSelectsThreadAndRefreshesTopBar() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(projects: [project]))

        let id = model.newChat(projectID: project.id)

        XCTAssertEqual(model.root.selectedThreadID, id)
        XCTAssertEqual(model.root.topBar.projectName, "QuillCode")
        XCTAssertEqual(model.root.topBar.threadTitle, "New chat")
        XCTAssertEqual(model.root.topBar.model, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(model.root.topBar.mode, .auto)
    }

    func testCommandPaletteSlashCommandPrefillsComposer() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        let command = try XCTUnwrap(
            WorkspaceCommandPalette.rankedCommands(model.surface().commands, matching: "/mode").first
        )

        XCTAssertTrue(model.runWorkspaceCommand(command.id, workspaceRoot: root))

        XCTAssertEqual(model.composer.draft, "/mode ")
    }

    func testSelectingProjectControlsNextChatAndWorkspaceRoot() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let projectID = model.addProject(path: root, name: "QuillCode")
        model.selectProject(projectID)
        let threadID = model.newChat()

        XCTAssertEqual(model.root.selectedProjectID, projectID)
        XCTAssertEqual(model.root.selectedThreadID, threadID)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
        XCTAssertEqual(model.selectedProject?.name, "QuillCode")
        XCTAssertEqual(model.activeWorkspaceRoot?.path, root.standardizedFileURL.path)
        XCTAssertEqual(model.root.topBar.projectName, "QuillCode")
    }

    func testProjectLifecycleActionsRenameRefreshNewChatAndRemove() throws {
        let root = try makeTempDirectory()
        try "Use focused tests.".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Original")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertTrue(model.renameProject(projectID, to: "Renamed Project"))
        XCTAssertEqual(model.selectedProject?.name, "Renamed Project")
        XCTAssertEqual(model.root.topBar.projectName, "Renamed Project")

        XCTAssertTrue(model.refreshProjectContext(projectID))
        XCTAssertEqual(model.selectedThread?.instructions.map(\.title), ["Project AGENTS.md"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Refreshed project context")

        XCTAssertTrue(model.runWorkspaceCommand("project-new-chat", workspaceRoot: root))
        XCTAssertNotEqual(model.root.selectedThreadID, threadID)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)

        XCTAssertTrue(model.runWorkspaceCommand("project-remove", workspaceRoot: root))
        XCTAssertTrue(model.root.projects.isEmpty)
        XCTAssertNil(model.root.selectedProjectID)
        XCTAssertNil(model.selectedThread?.projectID)
        XCTAssertNil(model.activeWorkspaceRoot)
    }

    func testNewChatIgnoresUnknownProjectID() {
        let model = QuillCodeWorkspaceModel()

        let threadID = model.newChat(projectID: UUID())

        XCTAssertEqual(model.root.selectedThreadID, threadID)
        XCTAssertNil(model.root.selectedProjectID)
        XCTAssertNil(model.selectedThread?.projectID)
        XCTAssertNil(model.root.topBar.projectName)
    }

    func testForkFromLastCreatesBoundedThreadFromLatestUserTurn() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "Project AGENTS.md",
                content: "Prefer focused tests.",
                byteCount: 21
            )
        ]
        let source = ChatThread(
            title: "Long thread",
            projectID: project.id,
            mode: .review,
            model: "z-ai/glm-5.2",
            messages: [
                .init(role: .user, content: "old question"),
                .init(role: .assistant, content: "old answer"),
                .init(role: .user, content: "latest question"),
                .init(role: .tool, content: #"{"result":"hidden continuation feedback"}"#),
                .init(role: .assistant, content: "latest answer")
            ],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [source],
            selectedThreadID: source.id
        ))

        let forkID = try XCTUnwrap(model.forkFromLast())
        let fork = try XCTUnwrap(model.root.threads.first { $0.id == forkID })

        XCTAssertEqual(fork.title, "Fork: Long thread")
        XCTAssertEqual(fork.projectID, project.id)
        XCTAssertEqual(fork.mode, .review)
        XCTAssertEqual(fork.model, "z-ai/glm-5.2")
        XCTAssertEqual(fork.instructions, instructions)
        XCTAssertEqual(fork.messages.map(\.content), ["latest question", "latest answer"])
        XCTAssertFalse(fork.messages.contains { $0.role == .tool })
        XCTAssertEqual(fork.events.first?.kind, .notice)
        XCTAssertEqual(fork.events.first?.payloadJSON, source.id.uuidString)
        XCTAssertEqual(model.root.selectedThreadID, forkID)
        XCTAssertEqual(model.root.selectedProjectID, project.id)
    }

    func testWorkspaceCommandForkFromLastSelectsFork() throws {
        let source = ChatThread(title: "Active", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "Output:\nquill")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("fork-from-last", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.selectedThread?.title, "Fork: Active")
        XCTAssertEqual(model.selectedThread?.messages.map(\.content), ["run whoami", "Output:\nquill"])
    }

    func testWorkspaceCommandCompactContextCreatesBoundedThread() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "Project AGENTS.md",
                content: "Use Swift.",
                byteCount: 10
            )
        ]
        let source = ChatThread(
            title: "Long context",
            projectID: project.id,
            mode: .review,
            model: "z-ai/glm-5.2",
            messages: [
                .init(role: .user, content: "old question one"),
                .init(role: .assistant, content: "old answer one"),
                .init(role: .user, content: "old question two"),
                .init(role: .assistant, content: "old answer two"),
                .init(role: .user, content: "latest request"),
                .init(role: .tool, content: #"{"result":"hidden continuation feedback"}"#),
                .init(role: .assistant, content: "latest answer")
            ],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [source],
            selectedThreadID: source.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("compact-context", workspaceRoot: try makeTempDirectory()))
        let compacted = try XCTUnwrap(model.selectedThread)

        XCTAssertEqual(compacted.title, "Compact: Long context")
        XCTAssertEqual(compacted.projectID, project.id)
        XCTAssertEqual(compacted.mode, .review)
        XCTAssertEqual(compacted.model, "z-ai/glm-5.2")
        XCTAssertEqual(compacted.instructions, instructions)
        XCTAssertEqual(compacted.messages.count, 3)
        XCTAssertTrue(compacted.messages[0].content.contains("Context compacted from \"Long context\""))
        XCTAssertTrue(compacted.messages[0].content.contains("summarized 4 earlier messages"))
        XCTAssertEqual(compacted.messages[1].content, "latest request")
        XCTAssertEqual(compacted.messages[2].content, "latest answer")
        XCTAssertFalse(compacted.messages.contains { $0.role == .tool })
        XCTAssertFalse(compacted.messages[0].content.contains("hidden continuation feedback"))
        XCTAssertEqual(compacted.events.first?.kind, .notice)
        XCTAssertEqual(compacted.events.first?.payloadJSON, source.id.uuidString)
    }

    func testSlashCommandsRouteToWorkspaceActions() async throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Project")
        model.selectProject(projectID)

        model.setDraft("/terminal")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertTrue(model.terminal.isVisible)

        await model.runTerminalCommand("printf slash-clear", workspaceRoot: root)
        XCTAssertFalse(model.terminal.entries.isEmpty)
        model.setDraft("/terminal clear")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertTrue(model.terminal.entries.isEmpty)
        XCTAssertTrue(model.terminal.isVisible)

        model.setDraft("/browser")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertTrue(model.browser.isVisible)

        model.setDraft("/worktrees")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.list")

        model.setDraft("/pr")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        model.setDraft("/project rename Slash Renamed")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedProject?.name, "Slash Renamed")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Renamed project to Slash Renamed.")

        model.setDraft("/project new")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
    }

    func testSlashEnvironmentActionListsAndRunsByName() async throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf slash-env-ok".write(
            to: actionsDirectory.appendingPathComponent("bootstrap-env.sh"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Env Project")
        model.selectProject(projectID)

        model.setDraft("/env")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.title, "Local environment actions")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("/env Bootstrap Env") == true)

        model.setDraft("/env bootstrap env")
        await model.submitComposer(workspaceRoot: root)
        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.shell.run")
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertEqual(result.stdout, "slash-env-ok")
    }

    func testSlashSSHAddsRemoteProjectAndDisablesLocalOnlyActions() async throws {
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
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-create" }?.isEnabled, false)
        XCTAssertEqual(model.selectedThread?.messages.last?.content.contains("Added SSH Remote"), true)
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
        XCTAssertTrue(toolNames.contains(ToolDefinition.planUpdate.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.browserInspect.name))
        XCTAssertFalse(toolNames.contains(ToolDefinition.gitCommit.name))
        XCTAssertFalse(toolNames.contains(ToolDefinition.gitPush.name))
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

    func testRemoteProjectRejectsUnavailableCommitTool() async throws {
        let root = try makeTempDirectory()
        let connection = ProjectConnection.ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.gitCommit.name,
                argumentsJSON: ToolArguments.json(["message": "ship it"])
            )))
        )

        model.setDraft("Commit the change")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Tool is not available") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))
    }

    func testSelectingProjectSelectsNewestThreadForThatProject() {
        let firstProject = ProjectRef(name: "One", path: "/tmp/one")
        let secondProject = ProjectRef(name: "Two", path: "/tmp/two")
        let older = ChatThread(
            title: "Older",
            projectID: firstProject.id,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ChatThread(
            title: "Newer",
            projectID: firstProject.id,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let other = ChatThread(title: "Other", projectID: secondProject.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [firstProject, secondProject],
            threads: [older, newer, other]
        ))

        model.selectProject(firstProject.id)

        XCTAssertEqual(model.root.selectedProjectID, firstProject.id)
        XCTAssertEqual(model.root.selectedThreadID, newer.id)
        XCTAssertEqual(model.root.topBar.threadTitle, "Newer")
        XCTAssertEqual(model.root.topBar.projectName, "One")
        XCTAssertEqual(model.selectedThread?.title, "Newer")
    }

    func testSubmitComposerRunsToolAndBuildsToolCard() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.composer.draft, "")
        XCTAssertFalse(model.composer.isSending)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.hasPrefix("You are `") == true)

        let cards = model.currentToolCards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "host.shell.run")
        XCTAssertEqual(cards[0].status, .done)
        XCTAssertTrue(cards[0].inputJSON?.contains("whoami") == true)
        XCTAssertTrue(cards[0].outputJSON?.contains("\"ok\" : true") == true)

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.messages.map(\.role), [.user, .tool, .assistant])
        XCTAssertEqual(QuillCodeWorkspaceModel.messageSurfaces(for: thread).map(\.role), [.user, .assistant])
        let timeline = QuillCodeWorkspaceModel.transcriptTimelineItems(for: thread)
        XCTAssertEqual(timeline.map(\.kind), [.message, .toolCard, .message])
        XCTAssertEqual(timeline[0].message?.role, .user)
        XCTAssertEqual(timeline[1].toolCard?.title, "host.shell.run")
        XCTAssertEqual(timeline[2].message?.role, .assistant)
    }

    func testMessageFeedbackIsStoredAndSurfaced() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let assistantMessage = try XCTUnwrap(model.selectedThread?.messages.last)
        XCTAssertEqual(assistantMessage.role, .assistant)
        XCTAssertTrue(model.setMessageFeedback(messageID: assistantMessage.id, value: .helpful))

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.events.last?.kind, .messageFeedback)
        XCTAssertEqual(QuillCodeWorkspaceModel.messageSurfaces(for: thread).last?.feedback, .helpful)
        XCTAssertEqual(QuillCodeWorkspaceModel.transcriptTimelineItems(for: thread).last?.message?.feedback, .helpful)
        XCTAssertFalse(model.setMessageFeedback(messageID: thread.messages[0].id, value: .notHelpful))
    }

    func testSubmitComposerSurfacesToolArtifacts() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.file.write")
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.artifacts.map(\.label), ["hello.txt"])
        XCTAssertEqual(card.artifacts.map(\.kind), [.file])
        XCTAssertEqual(card.artifacts.map(\.detail), [root.path])
        XCTAssertEqual(card.artifacts.first?.value, root.appendingPathComponent("hello.txt").path)
        XCTAssertEqual(card.artifacts.first?.textPreview, "hello world\n")
        XCTAssertEqual(card.textPreviewArtifacts.map(\.label), ["hello.txt"])
    }

    func testArtifactStateDerivesLinksAndImagePreviews() {
        let imageFile = ToolArtifactState(value: "/tmp/quillcode/screenshot.png")
        XCTAssertEqual(imageFile.kind, .file)
        XCTAssertEqual(imageFile.href, "file:///tmp/quillcode/screenshot.png")
        XCTAssertTrue(imageFile.isImagePreview)
        XCTAssertEqual(imageFile.previewURL, imageFile.href)
        XCTAssertEqual(imageFile.imagePreview?.typeLabel, "Image")
        XCTAssertEqual(imageFile.imagePreview?.extensionLabel, "PNG")
        XCTAssertEqual(imageFile.imagePreview?.detail, "/tmp/quillcode")

        let imageURL = ToolArtifactState(value: "https://example.com/assets/mock.webp?size=large")
        XCTAssertEqual(imageURL.kind, .url)
        XCTAssertEqual(imageURL.href, "https://example.com/assets/mock.webp?size=large")
        XCTAssertEqual(imageURL.label, "example.com/assets/mock.webp")
        XCTAssertTrue(imageURL.isImagePreview)
        XCTAssertEqual(imageURL.previewURL, imageURL.href)
        XCTAssertEqual(imageURL.imagePreview?.extensionLabel, "WEBP")
        XCTAssertEqual(imageURL.imagePreview?.detail, "example.com/assets/mock.webp")

        let inlineImage = ToolArtifactState(value: "data:image/png;base64,AAAA")
        XCTAssertEqual(inlineImage.kind, .url)
        XCTAssertEqual(inlineImage.label, "Inline image")
        XCTAssertEqual(inlineImage.detail, "Image artifact")
        XCTAssertTrue(inlineImage.isImagePreview)
        XCTAssertEqual(inlineImage.previewURL, "data:image/png;base64,AAAA")
        XCTAssertEqual(inlineImage.imagePreview?.extensionLabel, "PNG")
        XCTAssertEqual(inlineImage.imagePreview?.detail, "Image artifact")
        XCTAssertNil(inlineImage.textPreview)

        let nonImageData = ToolArtifactState(value: "data:text/plain;base64,SGVsbG8=")
        XCTAssertEqual(nonImageData.kind, .path)
        XCTAssertEqual(nonImageData.label, "data:text/plain;base64,SGVsbG8=")
        XCTAssertFalse(nonImageData.isImagePreview)
        XCTAssertNil(nonImageData.previewURL)
        XCTAssertNil(nonImageData.imagePreview)
        XCTAssertNil(nonImageData.href)
        XCTAssertNil(nonImageData.textPreview)
    }

    func testArtifactStateDerivesDocumentPreviews() {
        let pdfFile = ToolArtifactState(value: "/tmp/quillcode/reports/briefing.pdf")
        XCTAssertEqual(pdfFile.kind, .file)
        XCTAssertFalse(pdfFile.isImagePreview)
        XCTAssertTrue(pdfFile.isDocumentPreview)
        XCTAssertEqual(pdfFile.documentPreview?.kind, .pdf)
        XCTAssertEqual(pdfFile.documentPreview?.typeLabel, "PDF")
        XCTAssertEqual(pdfFile.documentPreview?.extensionLabel, "PDF")
        XCTAssertEqual(pdfFile.documentPreview?.detail, "/tmp/quillcode/reports")

        let spreadsheetURL = ToolArtifactState(value: "https://example.com/artifacts/budget.xlsx?download=1")
        XCTAssertEqual(spreadsheetURL.kind, .url)
        XCTAssertTrue(spreadsheetURL.isDocumentPreview)
        XCTAssertEqual(spreadsheetURL.documentPreview?.kind, .spreadsheet)
        XCTAssertEqual(spreadsheetURL.documentPreview?.typeLabel, "Spreadsheet")
        XCTAssertEqual(spreadsheetURL.documentPreview?.extensionLabel, "XLSX")
        XCTAssertEqual(spreadsheetURL.documentPreview?.detail, "example.com/artifacts/budget.xlsx")
        XCTAssertEqual(spreadsheetURL.href, "https://example.com/artifacts/budget.xlsx?download=1")

        let appshotBundle = ToolArtifactState(value: "/tmp/quillcode/appshots/checkout.appshot.json")
        XCTAssertEqual(appshotBundle.kind, .file)
        XCTAssertTrue(appshotBundle.isDocumentPreview)
        XCTAssertEqual(appshotBundle.documentPreview?.kind, .appshot)
        XCTAssertEqual(appshotBundle.documentPreview?.typeLabel, "Appshot")
        XCTAssertEqual(appshotBundle.documentPreview?.extensionLabel, "APPSHOT")
        XCTAssertEqual(appshotBundle.documentPreview?.detail, "/tmp/quillcode/appshots")

        let textFile = ToolArtifactState(value: "/tmp/quillcode/notes.md", textPreview: "# Notes\n")
        XCTAssertFalse(textFile.isDocumentPreview)
        XCTAssertTrue(textFile.hasTextPreview)
    }

    func testSubmitComposerDispatchesComputerUseToolThroughBackend() async throws {
        let root = try makeTempDirectory()
        let backend = StubComputerUseBackend()
        let call = ToolCall(
            name: ToolDefinition.computerClick.name,
            argumentsJSON: #"{"x":42,"y":84}"#
        )
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            computerUseBackend: backend
        )

        model.setDraft("click 42 84")
        await model.submitComposer(workspaceRoot: root)

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, ["leftClick:42,84"])
        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.computer.click")
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Computer Use completed: Clicked 42 84."
        )
    }

    func testSubmitComposerCapturesComputerUseScreenshotThroughBackend() async throws {
        let root = try makeTempDirectory()
        let backend = StubComputerUseBackend()
        let call = ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}")
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            computerUseBackend: backend
        )

        model.setDraft("take a screenshot")
        await model.submitComposer(workspaceRoot: root)

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, ["screenshot"])
        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.computer.screenshot")
        XCTAssertEqual(card.status, .done)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.stdout.contains(#""width" : 1"#))
        XCTAssertFalse(result.stdout.contains("pngBase64"))
        let screenshotArtifact = try XCTUnwrap(result.artifacts.first)
        defer {
            try? FileManager.default.removeItem(atPath: screenshotArtifact)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotArtifact))
        let artifact = try XCTUnwrap(card.artifacts.first)
        XCTAssertEqual(artifact.kind, .file)
        XCTAssertTrue(artifact.isImagePreview)
        XCTAssertEqual(artifact.previewURL, URL(fileURLWithPath: screenshotArtifact).absoluteString)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Captured a screenshot (1 x 1)."
        )
    }

    func testSubmitComposerStreamsQueuedToolBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(
            llm: ImmediateToolLLMClient(),
            safety: SlowApprovingSafetyReviewer()
        ))

        model.setDraft("run pwd")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }

        try await waitUntil(timeoutSeconds: 1) {
            model.currentToolCards.first?.status == .queued
        }
        XCTAssertTrue(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, "Queued")

        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.currentToolCards.first?.status, .done)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
    }

    func testComposerShowsStreamingStatusForStreamingLLM() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(
            llm: DelayedStreamingSayLLMClient(chunks: [
                #"{"type":"say","text":"stream"#,
                #"ed response"}"#
            ])
        ))

        model.setDraft("say hello")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }

        try await waitUntil(timeoutSeconds: 1) {
            model.root.topBar.agentStatus == "Streaming"
        }
        XCTAssertTrue(model.composer.isSending)
        try await waitUntil(timeoutSeconds: 1) {
            model.selectedThread?.messages.last?.content == "stream"
        }
        XCTAssertEqual(model.surface().transcript.timelineItems.last?.message?.text, "stream")

        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "streamed response")
        XCTAssertEqual(model.selectedThread?.events.map(\.kind), [.message, .notice, .message])
        XCTAssertEqual(model.selectedThread?.events[1].summary, AgentRunner.streamingNotice)
    }

    func testCancellingComposerRunStopsStateAndRecordsNotice() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowLLMClient()))

        model.setDraft("run a long task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.root.topBar.agentStatus, "Stopped")
        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.messages.map(\.role), [.user])
        XCTAssertEqual(thread.messages.first?.content, "run a long task")
        XCTAssertTrue(thread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
    }

    func testCancelledComposerRunRecordsNoticeOnOriginalThread() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowLLMClient()))
        let firstThreadID = model.newChat()

        model.setDraft("run a long task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }
        let secondThreadID = model.newChat()

        task.cancel()
        await task.value

        XCTAssertEqual(model.root.selectedThreadID, secondThreadID)
        let firstThread = try XCTUnwrap(model.root.threads.first { $0.id == firstThreadID })
        let secondThread = try XCTUnwrap(model.root.threads.first { $0.id == secondThreadID })
        XCTAssertTrue(firstThread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
        XCTAssertFalse(secondThread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
    }

    func testTerminalCommandRunsInWorkspaceRootAndRecordsOutput() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Terminal Project")
        model.selectProject(projectID)

        model.toggleTerminal()
        await model.runTerminalCommand("printf terminal-ok", workspaceRoot: root)

        XCTAssertTrue(model.terminal.isVisible)
        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].command, "printf terminal-ok")
        XCTAssertEqual(model.terminal.entries[0].stdout, "terminal-ok")
        XCTAssertEqual(model.terminal.entries[0].exitCode, 0)
        XCTAssertTrue(model.terminal.entries[0].ok)

        let surface = model.surface().terminal
        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.cwdLabel, root.path)
        XCTAssertEqual(surface.entries.first?.statusLabel, "Done")
        XCTAssertEqual(surface.entries.first?.exitCodeLabel, "exit 0")
    }

    func testTerminalCommandAppearsAsRunningBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 0.2 && printf terminal-done", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.isRunning && model.terminal.entries.first?.status == .running
        }

        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].command, "sleep 0.2 && printf terminal-done")
        XCTAssertEqual(model.surface().terminal.entries.first?.statusLabel, "Running")
        XCTAssertEqual(model.surface().terminal.entries.first?.exitCodeLabel, "running")

        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "terminal-done")
    }

    func testTerminalCommandStreamsOutputBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("echo terminal-start; sleep 0.2; echo terminal-end", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
                && model.terminal.entries.first?.stdout.contains("terminal-start") == true
        }

        XCTAssertEqual(model.surface().terminal.entries.first?.statusLabel, "Running")
        XCTAssertTrue(model.surface().terminal.entries.first?.stdout.contains("terminal-start") == true)

        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.first?.status, .done)
        XCTAssertTrue(model.terminal.entries.first?.stdout.contains("terminal-end") == true)
    }

    func testTerminalCommandRunsThroughSSHRemoteProject() async throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: "/srv/quill repo",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        await model.runTerminalCommand("printf remote-terminal", workspaceRoot: root)

        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "remote-terminal\n")
        XCTAssertEqual(model.terminal.currentDirectoryPath, "ssh://quill@feather.local:2222/srv/quill repo")
        let surface = model.surface()
        XCTAssertEqual(surface.terminal.cwdLabel, "ssh://quill@feather.local:2222/srv/quill repo")
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.kind, .sshRemote)
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.label, "SSH Remote")
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.detail, "feather.local")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("-T\n-o\nBatchMode=yes\n-o\nConnectTimeout=4\n-p\n2222\nquill@feather.local\n"))
        XCTAssertTrue(arguments.contains("cd '/srv/quill repo' &&"))
        XCTAssertTrue(arguments.contains("printf remote-terminal"))
        XCTAssertTrue(arguments.contains("__QUILLCODE_TERMINAL_"))
    }

    func testTerminalCommandPersistsSSHRemoteCWDAndEnvironment() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = root.appendingPathComponent("remote repo")
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
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

        await model.runTerminalCommand(
            "mkdir -p nested && cd nested && export QUILL_REMOTE_TERMINAL=works && printf remote-one",
            workspaceRoot: root
        )

        let nestedPath = remoteRoot.appendingPathComponent("nested").path
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "remote-one")
        XCTAssertEqual(model.terminal.currentDirectoryPath, "ssh://quill@feather.local\(nestedPath)")
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_REMOTE_TERMINAL"], "works")

        await model.runTerminalCommand(
            #"pwd && printf ':' && printf "$QUILL_REMOTE_TERMINAL""#,
            workspaceRoot: root
        )

        XCTAssertEqual(model.terminal.entries[1].status, .done)
        XCTAssertEqual(model.terminal.entries[1].stdout, "\(nestedPath)\n:works")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("cd '\(nestedPath.replacingOccurrences(of: "'", with: "'\\''"))' &&"))
    }

    func testTerminalCommandPersistsCurrentDirectoryAcrossCommands() async throws {
        let root = try makeTempDirectory()
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Terminal Project")

        await model.runTerminalCommand("cd nested", workspaceRoot: root)

        let resolvedNestedPath = nested.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertEqual(model.terminal.currentDirectoryPath, resolvedNestedPath)
        XCTAssertEqual(model.surface().terminal.cwdLabel, resolvedNestedPath)

        await model.runTerminalCommand("pwd", workspaceRoot: root)

        let printedPath = try XCTUnwrap(model.terminal.entries.last?.stdout)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            URL(fileURLWithPath: printedPath).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: try XCTUnwrap(model.terminal.currentDirectoryPath)).resolvingSymlinksInPath().path
        )
    }

    func testTerminalCommandPersistsEnvironmentAcrossCommands() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Terminal Project")

        await model.runTerminalCommand("export QUILL_TERMINAL_TEST=from-session", workspaceRoot: root)
        await model.runTerminalCommand("printf '%s' \"$QUILL_TERMINAL_TEST\"", workspaceRoot: root)

        XCTAssertEqual(model.terminal.entries.last?.stdout, "from-session")
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_TERMINAL_TEST"], "from-session")
        XCTAssertNil(model.terminal.environmentOverrides["SHLVL"])
        XCTAssertNil(model.terminal.environmentOverrides["PWD"])

        await model.runTerminalCommand("unset QUILL_TERMINAL_TEST", workspaceRoot: root)
        await model.runTerminalCommand("printf '%s' \"${QUILL_TERMINAL_TEST:-missing}\"", workspaceRoot: root)

        XCTAssertEqual(model.terminal.entries.last?.stdout, "missing")
    }

    func testTerminalClearHistoryKeepsSessionContextAndDraft() async throws {
        let root = try makeTempDirectory()
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Terminal Project")

        await model.runTerminalCommand(
            "cd nested && export QUILL_TERMINAL_TEST=from-clear",
            workspaceRoot: root
        )
        model.setTerminalDraft("pwd")

        XCTAssertTrue(model.surface().terminal.canClear)
        XCTAssertTrue(model.clearTerminalHistory())

        XCTAssertTrue(model.terminal.isVisible)
        XCTAssertTrue(model.terminal.entries.isEmpty)
        XCTAssertEqual(model.terminal.draft, "pwd")
        XCTAssertEqual(model.terminal.currentDirectoryPath, nested.standardizedFileURL.path)
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_TERMINAL_TEST"], "from-clear")
        XCTAssertFalse(model.surface().terminal.canClear)
        XCTAssertEqual(model.surface().terminal.cwdLabel, nested.standardizedFileURL.path)
    }

    func testTerminalClearHistoryDoesNotHideRunningCommand() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 5", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
        }

        XCTAssertFalse(model.clearTerminalHistory())
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries.first?.status, .running)
        XCTAssertFalse(model.surface().terminal.canClear)

        task.cancel()
        model.cancelActiveWork()
        await task.value
    }

    func testTerminalCurrentDirectoryResetsWhenProjectChanges() async throws {
        let firstRoot = try makeTempDirectory()
        let firstNested = firstRoot.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: firstNested, withIntermediateDirectories: true)
        let secondRoot = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: firstRoot, name: "First")

        await model.runTerminalCommand("cd nested", workspaceRoot: firstRoot)
        XCTAssertEqual(model.surface().terminal.cwdLabel, firstNested.standardizedFileURL.path)

        _ = model.addProject(path: secondRoot, name: "Second")

        XCTAssertEqual(model.surface().terminal.cwdLabel, secondRoot.standardizedFileURL.path)
        XCTAssertEqual(model.terminal.currentDirectoryPath, secondRoot.standardizedFileURL.path)
    }

    func testTerminalEnvironmentResetsWhenProjectChanges() async throws {
        let firstRoot = try makeTempDirectory()
        let secondRoot = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: firstRoot, name: "First")

        await model.runTerminalCommand("export QUILL_TERMINAL_TEST=from-first-project", workspaceRoot: firstRoot)
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_TERMINAL_TEST"], "from-first-project")

        _ = model.addProject(path: secondRoot, name: "Second")
        await model.runTerminalCommand("printf '%s' \"${QUILL_TERMINAL_TEST:-missing}\"", workspaceRoot: secondRoot)

        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_TERMINAL_TEST"], nil)
        XCTAssertEqual(model.terminal.entries.last?.stdout, "missing")
    }

    func testTerminalCancellationMarksRunningEntryStopped() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 5", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
        }

        task.cancel()
        model.cancelActiveWork()
        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .stopped)
        XCTAssertEqual(model.surface().terminal.entries.first?.statusLabel, "Stopped")
        XCTAssertEqual(model.surface().terminal.entries.first?.exitCodeLabel, "stopped")
        XCTAssertTrue(model.terminal.entries[0].stderr.contains("Command stopped."))
    }

    func testTerminalStopAllKeepsEntryStoppedAfterProcessExits() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 0.2 && printf late-result", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
        }

        model.cancelActiveWork()
        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .stopped)
        XCTAssertEqual(model.terminal.entries[0].stdout, "")
        XCTAssertEqual(model.terminal.entries[0].stderr, "Command stopped.")
        XCTAssertNil(model.terminal.entries[0].exitCode)
    }

    func testBrowserPreviewNormalizesURLsAndStoresComments() throws {
        let root = try makeTempDirectory()
        let previewFile = root.appendingPathComponent("preview.html")
        try """
        <!doctype html>
        <html>
          <head><title>Preview Page</title><script src="/app.js"></script></head>
          <body>
            <h1>Hero Preview</h1>
            <a href="/next">Next</a>
            <button>Buy now</button>
            <img src="/hero.png" alt="">
            <form><input name="email"></form>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("toggle-browser", workspaceRoot: root))
        XCTAssertTrue(model.browser.isVisible)

        XCTAssertTrue(model.openBrowserPreview("localhost:3000", workspaceRoot: root))
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(model.browser.title, "localhost")
        XCTAssertEqual(model.browser.status, "Preview ready")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Local web app")
        XCTAssertEqual(model.browser.snapshot?.inspectionDepth, .metadataOnly)
        XCTAssertEqual(
            model.browser.snapshot?.summary,
            "Live DOM capture is not attached yet; QuillCode has URL metadata for this local page."
        )
        XCTAssertEqual(model.browser.snapshot?.details, [
            "Host: localhost",
            "Scheme: HTTP",
            "Path: /"
        ])

        XCTAssertTrue(model.openBrowserPreview("preview.html", workspaceRoot: root))
        XCTAssertEqual(model.browser.currentURL, previewFile.standardizedFileURL.resolvingSymlinksInPath().absoluteString)
        XCTAssertEqual(model.browser.title, "Preview Page")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Local HTML")
        XCTAssertEqual(model.browser.snapshot?.inspectionDepth, .staticHTMLSnapshot)
        XCTAssertEqual(model.browser.snapshot?.summary, "HTML snapshot captured for browser review.")
        XCTAssertEqual(model.browser.snapshot?.details.filter { $0 == "Title: Preview Page" }.count, 1)
        XCTAssertEqual(model.browser.snapshot?.details.filter { $0 == "Heading: Hero Preview" }.count, 1)
        XCTAssertEqual(model.browser.snapshot.map { Array($0.details.suffix(4)) }, [
            "Links: 1",
            "Scripts: 1",
            "Images: 1",
            "Forms: 1"
        ])
        XCTAssertTrue(model.browser.snapshot?.outline.contains("H1: Hero Preview") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Link: Next -> /next") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Button: Buy now") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Input: email") == true)
        XCTAssertTrue(model.browser.snapshot?.textSnippet?.contains("Hero Preview Next Buy now") == true)

        XCTAssertTrue(model.addBrowserComment("Check the hero spacing"))
        XCTAssertEqual(model.browser.comments.count, 1)
        XCTAssertEqual(model.browser.comments[0].text, "Check the hero spacing")
        XCTAssertEqual(model.browser.comments[0].url, model.browser.currentURL)

        let inspectionResult = model.runToolCall(
            ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
            workspaceRoot: root
        )
        XCTAssertTrue(inspectionResult.ok)
        let inspection = try JSONHelpers.decode(BrowserInspectionToolOutput.self, from: inspectionResult.stdout)
        XCTAssertEqual(inspection.title, "Preview Page")
        XCTAssertEqual(inspection.sourceLabel, "Local HTML")
        XCTAssertEqual(inspection.inspectionDepth, .staticHTMLSnapshot)
        XCTAssertTrue(inspection.outline.contains("H1: Hero Preview"))
        XCTAssertEqual(inspection.comments.map(\.text), ["Check the hero spacing"])

        XCTAssertFalse(model.openBrowserPreview("not-a-valid-target", workspaceRoot: root))
        XCTAssertEqual(model.browser.status, "Invalid address")
        XCTAssertEqual(model.lastError, "Enter an http, https, file, localhost, or project file URL.")
    }

    func testBrowserPreviewSupportsHistoryNavigationAndReload() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.openBrowserPreview("localhost:3000"))
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertFalse(model.browser.canGoBack)
        XCTAssertFalse(model.browser.canGoForward)
        XCTAssertTrue(model.browser.canReload)

        XCTAssertTrue(model.openBrowserPreview("localhost:5173/dashboard"))
        XCTAssertEqual(model.browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(model.browser.history, [
            "http://localhost:3000",
            "http://localhost:5173/dashboard"
        ])
        XCTAssertEqual(model.browser.historyIndex, 1)
        XCTAssertTrue(model.browser.canGoBack)
        XCTAssertFalse(model.browser.canGoForward)

        XCTAssertTrue(model.goBackInBrowser())
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(model.browser.historyIndex, 0)
        XCTAssertFalse(model.browser.canGoBack)
        XCTAssertTrue(model.browser.canGoForward)

        XCTAssertTrue(model.reloadBrowserPreview())
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(model.browser.status, "Reloaded")
        XCTAssertEqual(model.browser.history, [
            "http://localhost:3000",
            "http://localhost:5173/dashboard"
        ])
        XCTAssertEqual(model.browser.historyIndex, 0)

        XCTAssertTrue(model.openBrowserPreview("example.com"))
        XCTAssertEqual(model.browser.currentURL, "https://example.com")
        XCTAssertEqual(model.browser.history, [
            "http://localhost:3000",
            "https://example.com"
        ])
        XCTAssertEqual(model.browser.historyIndex, 1)
        XCTAssertFalse(model.browser.canGoForward)
    }

    func testBrowserPreviewFetchesReachableHTMLSnapshot() async throws {
        let model = QuillCodeWorkspaceModel()
        let html = """
        <!doctype html>
        <html>
          <head><title>Running App</title></head>
          <body>
            <h1>Dashboard</h1>
            <a href="/settings">Settings</a>
            <button>Launch</button>
            <form aria-label="Search"><input placeholder="Find files"></form>
          </body>
        </html>
        """
        let fetcher = FakeBrowserPageFetcher(result: .success(BrowserFetchedPage(
            finalURL: URL(string: "http://localhost:5173/dashboard")!,
            statusCode: 200,
            contentType: "text/html; charset=utf-8",
            html: html,
            byteCount: 512,
            wasTruncated: false
        )))

        let didOpen = await model.openBrowserPreview("localhost:5173", pageFetcher: fetcher)
        XCTAssertTrue(didOpen)

        XCTAssertEqual(model.browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(model.browser.addressDraft, "http://localhost:5173/dashboard")
        XCTAssertEqual(model.browser.title, "Running App")
        XCTAssertEqual(model.browser.status, "Preview ready")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Local web app")
        XCTAssertEqual(model.browser.snapshot?.inspectionDepth, .staticHTMLSnapshot)
        XCTAssertEqual(model.browser.snapshot?.summary, "Fetched an HTML snapshot for this local page.")
        XCTAssertTrue(model.browser.snapshot?.details.contains("HTTP: 200") == true)
        XCTAssertTrue(model.browser.snapshot?.details.contains("Content-Type: text/html; charset=utf-8") == true)
        XCTAssertTrue(model.browser.snapshot?.details.contains("Size: 512 bytes") == true)
        XCTAssertTrue(model.browser.snapshot?.details.contains("Title: Running App") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("H1: Dashboard") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Link: Settings -> /settings") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Button: Launch") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Input: Find files") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Form: Search") == true)
        XCTAssertTrue(model.browser.snapshot?.textSnippet?.contains("Dashboard Settings Launch") == true)
    }

    func testBrowserPreviewKeepsMetadataSnapshotWhenHTMLFetchFails() async throws {
        let model = QuillCodeWorkspaceModel()
        let fetcher = FakeBrowserPageFetcher(result: .failure(.httpStatus(503)))

        let didOpen = await model.openBrowserPreview("example.com", pageFetcher: fetcher)
        XCTAssertTrue(didOpen)

        XCTAssertEqual(model.browser.currentURL, "https://example.com")
        XCTAssertEqual(model.browser.title, "example.com")
        XCTAssertEqual(model.browser.status, "Preview ready")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Web page")
        XCTAssertEqual(model.browser.snapshot?.inspectionDepth, .metadataOnly)
        XCTAssertTrue(model.browser.snapshot?.details.contains("Snapshot fetch: The page returned HTTP 503.") == true)
        XCTAssertNil(model.lastError)
    }

    func testComposerCanInspectCurrentBrowserPage() async throws {
        let root = try makeTempDirectory()
        let previewFile = root.appendingPathComponent("preview.html")
        try """
        <!doctype html>
        <html>
          <head><title>Browser Agent</title></head>
          <body>
            <h1>Agent Preview</h1>
            <p>Visible copy.</p>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.openBrowserPreview("preview.html", workspaceRoot: root))
        model.setDraft("inspect browser page")
        await model.submitComposer(workspaceRoot: root)

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertTrue(thread.events.contains { $0.summary.contains(ToolDefinition.browserInspect.name) })
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.browserInspect.name)
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
        XCTAssertTrue(thread.messages.last?.content.contains("Inspected `Browser Agent`") == true)
        XCTAssertTrue(thread.messages.last?.content.contains("H1: Agent Preview") == true)
        XCTAssertTrue(thread.messages.last?.content.contains("Visible copy.") == true)
    }

    func testWorkspaceCommandListsGitWorktrees() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Worktree Project")
        model.selectProject(projectID)

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-list", workspaceRoot: root))

        let cards = model.currentToolCards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "host.git.worktree.list")
        XCTAssertEqual(cards[0].status, .done)
        let outputJSON = try XCTUnwrap(cards[0].outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.stdout.contains(root.standardizedFileURL.path), result.stdout)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
    }

    func testWorkspaceWorktreeCommandsPrefillComposer() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a git worktree named ")

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-remove", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Remove git worktree at ")
    }

    func testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let worktreeName = "quillcode-ui-\(UUID().uuidString)"
        let branch = "quillcode-ui-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Worktree Project")
        model.selectProject(projectID)

        model.createWorktree(.init(path: worktreeName, branch: String(branch)), workspaceRoot: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.selectedProject?.path, worktree.path)
        XCTAssertEqual(model.selectedProject?.name, worktreeName)
        XCTAssertEqual(model.selectedThread?.projectID, model.selectedProject?.id)
        XCTAssertEqual(model.selectedThread?.title, "Worktree: \(branch)")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Opened worktree `\(worktreeName)`") == true)
        XCTAssertEqual(model.root.topBar.projectName, worktreeName)
        XCTAssertEqual(model.root.topBar.threadTitle, "Worktree: \(branch)")

        let createThread = try XCTUnwrap(model.root.threads.first { thread in
            QuillCodeWorkspaceModel.toolCards(for: thread).contains { card in
                card.title == "host.git.worktree.create"
            }
        })
        XCTAssertNotEqual(createThread.id, model.selectedThread?.id)
        let createCard = try XCTUnwrap(QuillCodeWorkspaceModel.toolCards(for: createThread).last)
        XCTAssertEqual(createCard.status, .done)
        XCTAssertTrue(createCard.inputJSON?.contains(worktreeName) == true)

        model.removeWorktree(.init(path: worktreeName), workspaceRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.remove")
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
    }

    func testApplyPatchToolRunRefreshesReviewDiff() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let fileURL = root.appendingPathComponent("hello.txt")
        try "old\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let model = QuillCodeWorkspaceModel()

        model.runToolCall(
            ToolCall(
                name: ToolDefinition.applyPatch.name,
                argumentsJSON: ToolArguments.json(["patch": patch])
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "new\n")
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            "host.apply_patch",
            "host.git.diff"
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertTrue(model.surface().review.isVisible)
        XCTAssertEqual(model.surface().review.files.map(\.path), ["hello.txt"])
        let lines = try XCTUnwrap(model.surface().review.files.first?.hunkItems.first?.lines)
        XCTAssertTrue(lines.contains(where: {
            $0.content == "new" && $0.kind == .insertion
        }))
    }

    func testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun() async throws {
        let root = try makeTempDirectory()
        try "Prefer Swift tests before final answers.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let quillcodeDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillcodeDirectory, withIntermediateDirectories: true)
        try "Use small focused commits.\n".write(
            to: quillcodeDirectory.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Rules Project")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertEqual(model.root.projects.first?.instructions.map(\.path), [
            "AGENTS.md",
            ".quillcode/rules.md"
        ])
        XCTAssertEqual(model.root.threads.first { $0.id == threadID }?.instructions.count, 2)
        XCTAssertEqual(model.surface().topBar.instructionLabel, "2 instruction files loaded")

        try "Prefer targeted unit tests.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertTrue(model.selectedThread?.instructions.first?.content.contains("targeted unit tests") == true)
    }

    func testProjectInstructionLoaderBoundsFilesAndRejectsSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory().appendingPathComponent("outside.md")
        try "outside rules\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("AGENTS.md"),
            withDestinationURL: outside
        )
        let quillcodeDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillcodeDirectory, withIntermediateDirectories: true)
        try String(repeating: "x", count: 64).write(
            to: quillcodeDirectory.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let instructions = ProjectInstructionLoader.load(
            from: root,
            maxFileBytes: 12,
            maxTotalBytes: 20
        )

        XCTAssertEqual(instructions.map(\.path), [".quillcode/rules.md"])
        XCTAssertTrue(instructions[0].wasTruncated)
        XCTAssertTrue(instructions[0].content.contains("truncated"))
        XCTAssertFalse(instructions[0].content.contains("outside rules"))
    }

    func testProjectInstructionLoaderLoadsNestedInstructionsInPrecedenceOrder() throws {
        let root = try makeTempDirectory()
        try "Root rules\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let feature = root.appendingPathComponent("Sources/Feature")
        try FileManager.default.createDirectory(at: feature, withIntermediateDirectories: true)
        try "Sources rules\n".write(
            to: root.appendingPathComponent("Sources/AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Feature rules\n".write(
            to: feature.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let featureQuillCode = feature.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: featureQuillCode, withIntermediateDirectories: true)
        try "Feature QuillCode rules\n".write(
            to: featureQuillCode.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let generated = root.appendingPathComponent(".build/generated")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try "Generated rules should not load\n".write(
            to: generated.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let instructions = ProjectInstructionLoader.load(from: root)

        XCTAssertEqual(instructions.map(\.path), [
            "AGENTS.md",
            "Sources/AGENTS.md",
            "Sources/Feature/AGENTS.md",
            "Sources/Feature/.quillcode/rules.md"
        ])
        XCTAssertTrue(instructions.last?.content.contains("Feature QuillCode rules") == true)
        XCTAssertFalse(instructions.contains { $0.content.contains("Generated rules") })
    }

    func testProjectInstructionLoaderCapsNestedInstructionCount() throws {
        let root = try makeTempDirectory()
        for index in 0..<5 {
            let directory = root.appendingPathComponent("Area\(index)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "Rules \(index)\n".write(
                to: directory.appendingPathComponent("AGENTS.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let instructions = ProjectInstructionLoader.load(
            from: root,
            maxInstructionFiles: 2
        )

        XCTAssertEqual(instructions.map(\.path), [
            "Area0/AGENTS.md",
            "Area1/AGENTS.md"
        ])
    }

    func testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs() throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf local-env-ok".write(
            to: actionsDirectory.appendingPathComponent("bootstrap-env.sh"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Local Env Project")
        model.selectProject(projectID)

        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        XCTAssertEqual(action.title, "Bootstrap Env")
        XCTAssertEqual(action.relativePath, ".quillcode/actions/bootstrap-env.sh")
        XCTAssertTrue(model.runWorkspaceCommand(action.id, workspaceRoot: root))

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.shell.run")
        XCTAssertEqual(card.status, .done)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertEqual(result.stdout, "local-env-ok")
    }

    func testLocalEnvironmentActionLoaderUsesMetadataSidecars() throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf second".write(
            to: actionsDirectory.appendingPathComponent("z-second.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Second Check",
          "description": "Runs after dependencies are ready.",
          "order": 20
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("z-second.json"),
            atomically: true,
            encoding: .utf8
        )
        try "printf first".write(
            to: actionsDirectory.appendingPathComponent("a-first.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Prepare Workspace",
          "description": "Install dependencies and warm caches.",
          "order": 10
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("a-first.json"),
            atomically: true,
            encoding: .utf8
        )

        let actions = LocalEnvironmentActionLoader.load(from: root)

        XCTAssertEqual(actions.map(\.title), ["Prepare Workspace", "Second Check"])
        XCTAssertEqual(actions.map(\.detail), [
            "Install dependencies and warm caches.",
            "Runs after dependencies are ready."
        ])
        XCTAssertEqual(actions.map(\.relativePath), [
            ".quillcode/actions/a-first.sh",
            ".quillcode/actions/z-second.sh"
        ])
        XCTAssertEqual(actions[0].command, #"sh '.quillcode/actions/a-first.sh'"#)
    }

    func testLocalEnvironmentActionMetadataInjectsBoundedEnvironment() throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try #"printf "%s|%s|%s|%s" "$QUILL_ENV" "$CACHE_DIR" "$QUOTED_VALUE" "$(printenv BAD-KEY || true)""#.write(
            to: actionsDirectory.appendingPathComponent("env-check.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Environment Check",
          "environment": {
            "QUILL_ENV": "dev",
            "CACHE_DIR": ".cache/quill",
            "QUOTED_VALUE": "it's ok",
            "BAD-KEY": "ignored",
            "MULTILINE": "bad\\nvalue"
          }
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("env-check.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Local Env Metadata Project")
        model.selectProject(projectID)

        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        XCTAssertEqual(action.title, "Environment Check")
        XCTAssertEqual(action.environment, [
            "CACHE_DIR": ".cache/quill",
            "QUILL_ENV": "dev",
            "QUOTED_VALUE": "it's ok"
        ])
        XCTAssertEqual(
            action.command,
            #"sh '.quillcode/actions/env-check.sh'"#
        )
        XCTAssertTrue(model.runWorkspaceCommand(action.id, workspaceRoot: root))

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertTrue(card.inputJSON?.contains(#""environment""#) == true)
        XCTAssertTrue(card.inputJSON?.contains("QUILL_ENV") == true)
        XCTAssertTrue(card.inputJSON?.contains(ToolCall.redactedEnvironmentValue) == true)
        XCTAssertFalse(card.inputJSON?.contains(".cache/quill") == true)
        XCTAssertFalse(card.inputJSON?.contains("it's ok") == true)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertEqual(result.stdout, "dev|.cache/quill|it's ok|")
    }

    func testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory() throws {
        let root = try makeTempDirectory()
        let appDirectory = root.appendingPathComponent("app")
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "marker-ok".write(
            to: appDirectory.appendingPathComponent("marker.txt"),
            atomically: true,
            encoding: .utf8
        )
        try #"printf "%s|%s" "$(basename "$PWD")" "$(cat marker.txt)""#.write(
            to: actionsDirectory.appendingPathComponent("cwd-check.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "CWD Check",
          "workingDirectory": "app"
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("cwd-check.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Local Env CWD Project")
        model.selectProject(projectID)

        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        XCTAssertEqual(action.workingDirectory, "app")
        XCTAssertEqual(action.command, #"cd 'app' && sh '../.quillcode/actions/cwd-check.sh'"#)
        XCTAssertTrue(model.runWorkspaceCommand(action.id, workspaceRoot: root))

        let card = try XCTUnwrap(model.currentToolCards.last)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertEqual(result.stdout, "app|marker-ok")
    }

    func testLocalEnvironmentActionMetadataPassesBoundedTimeout() throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "sleep 2; printf should-not-print".write(
            to: actionsDirectory.appendingPathComponent("slow.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Slow Check",
          "timeoutSeconds": 1
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("slow.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Local Env Timeout Project")
        model.selectProject(projectID)

        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        XCTAssertEqual(action.timeoutSeconds, 1)
        XCTAssertTrue(model.runWorkspaceCommand(action.id, workspaceRoot: root))

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.status, .failed)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Command timed out after 1s.")
    }

    func testLocalEnvironmentActionLoaderRejectsUnsafeWorkingDirectory() throws {
        let root = try makeTempDirectory()
        let outsideDirectory = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outsideDirectory
        )
        try "printf safe".write(
            to: actionsDirectory.appendingPathComponent("safe.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Safe",
          "workingDirectory": "escape"
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("safe.json"),
            atomically: true,
            encoding: .utf8
        )

        let action = try XCTUnwrap(LocalEnvironmentActionLoader.load(from: root).first)

        XCTAssertNil(action.workingDirectory)
        XCTAssertEqual(action.command, #"sh '.quillcode/actions/safe.sh'"#)
    }

    func testLocalEnvironmentActionLoaderRejectsUnsafeTimeoutSeconds() throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf safe".write(
            to: actionsDirectory.appendingPathComponent("safe.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Safe",
          "timeout_seconds": 1801
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("safe.json"),
            atomically: true,
            encoding: .utf8
        )

        let action = try XCTUnwrap(LocalEnvironmentActionLoader.load(from: root).first)

        XCTAssertNil(action.timeoutSeconds)
    }

    func testSlashEnvironmentActionListShowsMetadataDescription() async throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf metadata-env-ok".write(
            to: actionsDirectory.appendingPathComponent("prepare.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Prepare Workspace",
          "description": "Install dependencies and warm caches."
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("prepare.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Env Metadata Project")
        model.selectProject(projectID)

        model.setDraft("/env")
        await model.submitComposer(workspaceRoot: root)

        let message = try XCTUnwrap(model.selectedThread?.messages.last?.content)
        XCTAssertTrue(message.contains("/env Prepare Workspace"))
        XCTAssertTrue(message.contains("Install dependencies and warm caches."))
    }

    func testLocalEnvironmentActionLoaderBoundsScriptsAndRejectsSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory().appendingPathComponent("outside.sh")
        try "printf bad".write(to: outside, atomically: true, encoding: .utf8)
        let outsideMetadata = outside.deletingPathExtension().appendingPathExtension("json")
        try """
        { "title": "Escaped Metadata" }
        """.write(to: outsideMetadata, atomically: true, encoding: .utf8)
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: actionsDirectory.appendingPathComponent("outside.sh"),
            withDestinationURL: outside
        )
        try "printf one".write(
            to: actionsDirectory.appendingPathComponent("one.sh"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: actionsDirectory.appendingPathComponent("one.json"),
            withDestinationURL: outsideMetadata
        )
        try "printf two".write(
            to: actionsDirectory.appendingPathComponent("two.sh"),
            atomically: true,
            encoding: .utf8
        )

        let actions = LocalEnvironmentActionLoader.load(from: root, maxActions: 1)

        XCTAssertEqual(actions.map(\.relativePath), [".quillcode/actions/one.sh"])
        XCTAssertEqual(actions[0].title, "One")
        XCTAssertEqual(actions[0].command, #"sh '.quillcode/actions/one.sh'"#)
    }

    func testProjectExtensionManifestLoaderLoadsKindsAndRejectsUnsafeFiles() throws {
        let root = try makeTempDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        let skillDirectory = root.appendingPathComponent(".quillcode/skills")
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)

        try #"{"id":"github","name":"GitHub","description":"PR and issue helpers."}"#.write(
            to: pluginDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"review","name":"Code Review","summary":"Review defects first.","enabled":false}"#.write(
            to: skillDirectory.appendingPathComponent("review.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"filesystem","name":"Filesystem MCP","command":"quill-mcp","args":["--root","."]}"#.write(
            to: mcpDirectory.appendingPathComponent("filesystem.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"broken""#.write(
            to: pluginDirectory.appendingPathComponent("broken.json"),
            atomically: true,
            encoding: .utf8
        )
        let outside = try makeTempDirectory().appendingPathComponent("outside.json")
        try #"{"id":"outside","name":"Outside"}"#.write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: pluginDirectory.appendingPathComponent("outside.json"),
            withDestinationURL: outside
        )

        let manifests = ProjectExtensionManifestLoader.load(from: root)

        XCTAssertEqual(manifests.map(\.id), [
            "plugin:github",
            "skill:review",
            "mcp_server:filesystem"
        ])
        XCTAssertEqual(manifests.map(\.kind), [.plugin, .skill, .mcpServer])
        XCTAssertEqual(manifests[0].summary, "PR and issue helpers.")
        XCTAssertEqual(manifests[1].isEnabled, false)
        XCTAssertEqual(manifests[2].transport, .stdio)
        XCTAssertEqual(manifests[2].launchExecutable, "quill-mcp")
        XCTAssertEqual(manifests[2].launchCommand, "quill-mcp --root .")
        XCTAssertEqual(manifests[2].launchArguments, ["--root", "."])
    }

    func testProjectExtensionManifestsLoadIntoProjectSurface() throws {
        let root = try makeTempDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try #"{"id":"github","name":"GitHub","description":"PR workflow helpers."}"#.write(
            to: pluginDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Extension Project")
        model.selectProject(projectID)
        XCTAssertTrue(model.runWorkspaceCommand("toggle-extensions", workspaceRoot: root))

        let extensions = model.surface().extensions

        XCTAssertTrue(extensions.isVisible)
        XCTAssertEqual(extensions.pluginCount, 1)
        XCTAssertEqual(extensions.skillCount, 0)
        XCTAssertEqual(extensions.mcpServerCount, 0)
        XCTAssertEqual(extensions.items.first?.name, "GitHub")
        XCTAssertEqual(extensions.items.first?.relativePath, ".quillcode/plugins/github.json")
    }

    func testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses() throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root, includeResourcesAndPrompts: true)
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
            to: mcpDirectory.appendingPathComponent("filesystem.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)
        model.toggleExtensions()

        XCTAssertEqual(model.surface().extensions.items.first?.statusLabel, "Stopped")
        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))

        var surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Ready")
        XCTAssertEqual(surface.extensions.items.first?.serverLabel, "Fixture MCP 1.0.0")
        XCTAssertEqual(surface.extensions.items.first?.protocolLabel, "MCP 2024-11-05")
        XCTAssertEqual(surface.extensions.items.first?.toolCountLabel, "2 tools")
        XCTAssertEqual(surface.extensions.items.first?.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(surface.extensions.items.first?.toolDescriptors.map(\.schemaSummary), [
            "required: path:string",
            "required: content:string, path:string; optional: overwrite:boolean"
        ])
        XCTAssertEqual(surface.extensions.items.first?.resourceCountLabel, "2 resources")
        XCTAssertEqual(surface.extensions.items.first?.resourceNames, ["README", "Project config"])
        XCTAssertEqual(surface.extensions.items.first?.promptCountLabel, "1 prompt")
        XCTAssertEqual(surface.extensions.items.first?.promptNames, ["summarize_project"])
        XCTAssertEqual(surface.extensions.items.first?.stopCommandID, "mcp-stop:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, true)
        XCTAssertTrue(model.selectedThread?.events.contains {
            $0.summary == "MCP server Filesystem MCP ready (2 tools: read_file, write_file; 2 resources; 1 prompt)"
        } == true)

        model.cancelActiveWork()
        surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Stopped")
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, false)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        XCTAssertTrue(model.runWorkspaceCommand("mcp-stop:mcp_server:filesystem", workspaceRoot: root))
        surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Stopped")
        XCTAssertEqual(surface.extensions.items.first?.startCommandID, "mcp-start:mcp_server:filesystem")
        XCTAssertTrue(model.selectedThread?.events.contains { $0.summary == "MCP server Filesystem MCP stopped" } == true)
    }

    func testReadyMCPServerCanBeCalledFromAgentTurn() async throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root, callText: "hello from MCP")
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","toolName":"read_file","arguments":{"path":"README.md"}}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: FixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("run MCP read_file on README")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(Array(model.selectedThread?.events.map(\.kind).suffix(5) ?? []), [
            .message,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .message
        ])
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Output:\nhello from MCP")
    }

    func testReadyMCPToolDescriptionIncludesSchemasForLLM() async throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root)
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let recorder = ToolDefinitionRecorder()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: RecordingLLMClient(recorder: recorder)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("use the MCP filesystem tool")
        await model.submitComposer(workspaceRoot: root)

        let mcpCall = try XCTUnwrap(recorder.tools.first { $0.name == ToolDefinition.mcpCall.name })
        XCTAssertTrue(mcpCall.description.contains("read_file [required: path:string; Read a file]"))
        XCTAssertTrue(mcpCall.description.contains("write_file [required: content:string, path:string; optional: overwrite:boolean]"))
    }

    func testReadyMCPResourceCanBeReadFromAgentTurn() async throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(
            in: root,
            includeResourcesAndPrompts: true,
            resourceText: "# MCP README"
        )
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpReadResource.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","resourceName":"README"}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: FixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("read the README MCP resource")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.selectedThread?.events.suffix(2).first?.kind, .toolCompleted)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.mcpReadResource.name)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "MCP resource contents:\n# MCP README"
        )
    }

    func testReadyMCPPromptCanBeLoadedFromAgentTurn() async throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(
            in: root,
            includeResourcesAndPrompts: true,
            promptText: "Summarize this workspace."
        )
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpGetPrompt.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","promptName":"summarize_project"}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: FixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("load the MCP summarize prompt")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.selectedThread?.events.suffix(2).first?.kind, .toolCompleted)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.mcpGetPrompt.name)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("MCP prompt:\nPrompt: summarize_project") == true)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("user: Summarize this workspace.") == true)
    }

    func testMCPToolCallRejectsUnadvertisedTools() async throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root, callText: "should not run")
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","toolName":"delete_everything","arguments":{}}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: FixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("run MCP delete_everything")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.selectedThread?.events.suffix(2).first?.kind, .toolFailed)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Command failed:\nMCP tool delete_everything was not advertised by mcp_server:filesystem."
        )
    }

    func testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface() async throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )
        let projectMemoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "This project uses SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Project")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertEqual(model.root.globalMemories.map(\.relativePath), ["memories/preferences.md"])
        XCTAssertEqual(model.root.projects.first?.memories.map(\.relativePath), [".quillcode/memories/project.md"])
        XCTAssertEqual(model.root.threads.first { $0.id == threadID }?.memories.map(\.title), ["Preferences", "Project"])

        XCTAssertTrue(model.runWorkspaceCommand("toggle-memories", workspaceRoot: root))
        let memories = model.surface().memories
        XCTAssertTrue(memories.isVisible)
        XCTAssertEqual(memories.globalCount, 1)
        XCTAssertEqual(memories.projectCount, 1)
        XCTAssertEqual(memories.items.map { $0.scope }, [MemoryScope.global, .project])
        XCTAssertEqual(memories.items.first?.canDelete, true)
        XCTAssertNotNil(memories.items.first?.deleteCommandID)
        XCTAssertEqual(memories.items.last?.canDelete, false)
        XCTAssertNil(memories.items.last?.deleteCommandID)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "2 memories")
    }

    func testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface() async throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Write Project")
        model.selectProject(projectID)

        model.setDraft("/remember Prefer small reviewable commits")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories.count, 1)
        let memory = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertEqual(memory.content, "Prefer small reviewable commits")
        XCTAssertTrue(memory.relativePath.hasPrefix("memories/manual-"))
        XCTAssertTrue(memory.relativePath.hasSuffix("-prefer-small-reviewable-commits.md"))
        XCTAssertEqual(model.selectedThread?.title, "Memory: \(memory.title)")
        XCTAssertEqual(model.selectedThread?.memories.map(\.content), ["Prefer small reviewable commits"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Saved memory: \(memory.title)")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, memory.relativePath)
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Saved memory: \(memory.title)") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")
        XCTAssertEqual(model.surface().memories.items.first?.canDelete, true)
        XCTAssertEqual(model.surface().memories.items.first?.deleteCommandID, "memory-delete:\(memory.id)")

        let filename = memory.relativePath.replacingOccurrences(of: "memories/", with: "")
        let savedURL = globalMemories.appendingPathComponent(filename)
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), "Prefer small reviewable commits\n")
    }

    func testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface() async throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Agent Memory Project")
        model.selectProject(projectID)

        model.setDraft("remember that I prefer small reviewable commits")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories.count, 1)
        let memory = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertEqual(memory.content, "I prefer small reviewable commits")
        XCTAssertEqual(model.selectedThread?.memories.map(\.content), ["I prefer small reviewable commits"])
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.memoryRemember.name)
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Saved memory: \(memory.title)") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")

        let filename = memory.relativePath.replacingOccurrences(of: "memories/", with: "")
        let savedURL = globalMemories.appendingPathComponent(filename)
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), "I prefer small reviewable commits\n")
    }

    func testAgentRememberToolRejectsCredentialLikeMemory() async throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.memoryRemember.name,
            argumentsJSON: ToolArguments.json([
                "content": "api_key=sk-qc-v1-ob4rbJAb9WOqdNIhSsT8oumjqaLZUX8p2zLHr1WOGn8"
            ])
        )
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            globalMemoryDirectory: globalMemories
        )

        model.setDraft("remember this api key")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: globalMemories.path)
                .filter { $0.hasSuffix(".md") },
            []
        )
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.memoryRemember.name)
        XCTAssertEqual(model.currentToolCards.last?.status, .failed)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("credential") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "No memories")
    }

    func testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface() throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )
        let projectMemoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "This project uses SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Delete Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        let global = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertTrue(model.runWorkspaceCommand("memory-delete:\(global.id)", workspaceRoot: root))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: globalMemories.appendingPathComponent("preferences.md").path
        ))
        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(model.selectedThread?.memories.map(\.relativePath), [".quillcode/memories/project.md"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Forgot memory: Preferences")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, "memories/preferences.md")
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Forgot memory: Preferences") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")
        XCTAssertEqual(model.surface().memories.items.map(\.scope), [.project])
    }

    func testMemoryDeleteRejectsUnknownGlobalMemoryIDWithoutRemovingFiles() throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        _ = model.newChat()

        XCTAssertTrue(model.runWorkspaceCommand("memory-delete:missing-memory", workspaceRoot: root))

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: globalMemories.appendingPathComponent("preferences.md").path
        ))
        XCTAssertEqual(model.root.globalMemories.map(\.relativePath), ["memories/preferences.md"])
        XCTAssertEqual(model.selectedThread?.title, "Memory not deleted")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("not found") == true)
    }

    func testSlashRememberRejectsCredentialLikeMemory() async throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)

        model.setDraft("/remember api_key=sk-qc-v1-ob4rbJAb9WOqdNIhSsT8oumjqaLZUX8p2zLHr1WOGn8")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: globalMemories.path)
                .filter { $0.hasSuffix(".md") },
            []
        )
        XCTAssertEqual(model.selectedThread?.title, "Memory not saved")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("credential") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "No memories")
    }

    func testMemoryAddWorkspaceCommandPrefillsRememberSlash() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("memory-add", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.composer.draft, "/remember ")
    }

    func testMemoryNoteLoaderBoundsFilesAndRejectsSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory().appendingPathComponent("outside.md")
        try "outside memory\n".write(to: outside, atomically: true, encoding: .utf8)
        let memoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: memoryDirectory.appendingPathComponent("outside.md"),
            withDestinationURL: outside
        )
        try String(repeating: "x", count: 64).write(
            to: memoryDirectory.appendingPathComponent("one.md"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored binary".write(
            to: memoryDirectory.appendingPathComponent("ignored.bin"),
            atomically: true,
            encoding: .utf8
        )

        let notes = MemoryNoteLoader.loadProject(
            from: root,
            maxNotes: 1,
            maxFileBytes: 12,
            maxTotalBytes: 12
        )

        XCTAssertEqual(notes.map(\.relativePath), [".quillcode/memories/one.md"])
        XCTAssertTrue(notes[0].wasTruncated)
        XCTAssertTrue(notes[0].content.contains("truncated"))
        XCTAssertFalse(notes[0].content.contains("outside memory"))
    }

    func testEmptyDraftDoesNotCreateThread() async throws {
        let model = QuillCodeWorkspaceModel()
        model.setDraft("   ")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())
        XCTAssertTrue(model.root.threads.isEmpty)
    }

    func testSlashNewCreatesFreshThreadWithoutAgentRun() async throws {
        let existing = ChatThread(title: "Existing")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [existing],
            selectedThreadID: existing.id
        ))

        model.setDraft("/new")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertEqual(model.composer.draft, "")
        XCTAssertEqual(model.root.threads.count, 2)
        XCTAssertEqual(model.selectedThread?.title, "New chat")
        XCTAssertTrue(model.selectedThread?.messages.isEmpty == true)
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashModeChangesModeAndWritesLocalTranscript() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/mode review")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertEqual(model.root.config.mode, .review)
        XCTAssertEqual(model.selectedThread?.mode, .review)
        XCTAssertEqual(model.selectedThread?.title, "Set mode")
        XCTAssertEqual(model.selectedThread?.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Mode set to Review.")
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashModelChangesModelAndWritesLocalTranscript() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/model z-ai/glm-5.2")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertEqual(model.root.config.defaultModel, "z-ai/glm-5.2")
        XCTAssertEqual(model.selectedThread?.model, "z-ai/glm-5.2")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Model set to z-ai/glm-5.2.")
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashCompactRoutesToContextCompaction() async throws {
        let source = ChatThread(title: "Long slash thread", messages: [
            .init(role: .user, content: "old question"),
            .init(role: .assistant, content: "old answer"),
            .init(role: .user, content: "latest question"),
            .init(role: .assistant, content: "latest answer")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))

        model.setDraft("/compact")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertEqual(model.selectedThread?.title, "Compact: Long slash thread")
        XCTAssertEqual(Array(model.selectedThread?.messages.map(\.content).suffix(2) ?? []), ["latest question", "latest answer"])
        XCTAssertTrue(model.selectedThread?.messages.first?.content.contains("Context compacted") == true)
    }

    func testSlashThreadLifecycleCommands() async throws {
        let source = ChatThread(title: "Original", messages: [
            .init(role: .user, content: "run whoami")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))
        let root = try makeTempDirectory()

        model.setDraft("/rename Better name")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.title, "Better name")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Renamed chat to Better name.")

        model.setDraft("/duplicate")
        await model.submitComposer(workspaceRoot: root)
        let duplicateID = try XCTUnwrap(model.root.selectedThreadID)
        XCTAssertEqual(model.selectedThread?.title, "Copy: Better name")

        model.setDraft("/archive")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.root.selectedThreadID, source.id)
        XCTAssertTrue(model.root.threads.first { $0.id == duplicateID }?.isArchived == true)

        model.selectThread(duplicateID)
        model.setDraft("/unarchive")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)
        XCTAssertFalse(model.selectedThread?.isArchived ?? true)
    }

    func testSlashStatusReportsWorkspaceState() async throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Status thread", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.setDraft("/status")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        let message = try XCTUnwrap(model.selectedThread?.messages.last?.content)
        XCTAssertTrue(message.contains("Project: QuillCode"))
        XCTAssertTrue(message.contains("Thread: Status thread"))
        XCTAssertTrue(message.contains("Mode: Auto"))
        XCTAssertTrue(message.contains("Model: trustedrouter/fast"))
    }

    func testPinnedThreadsSortBeforeRecentThreads() {
        let older = ChatThread(
            title: "Older",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        var newer = ChatThread(
            title: "Newer",
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        newer.isPinned = true
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [older, newer]))

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Newer", "Older"])
    }

    func testArchiveSelectedThreadRemovesItFromSidebar() {
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [first, second],
            selectedThreadID: first.id
        ))

        model.archiveSelectedThread()

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Second"])
        XCTAssertEqual(model.root.selectedThreadID, second.id)
    }

    func testPinAndArchiveThreadByIDPersistChanges() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root)
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        try threadStore.save(first)
        try threadStore.save(second)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [first, second],
                selectedThreadID: first.id
            ),
            threadStore: threadStore
        )

        model.togglePinThread(second.id)
        model.archiveThread(first.id)

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Second"])
        XCTAssertEqual(model.root.selectedThreadID, second.id)
        XCTAssertTrue(try threadStore.load(second.id).isPinned)
        XCTAssertTrue(try threadStore.load(first.id).isArchived)
    }

    func testRenameDuplicateUnarchiveAndDeleteThreadLifecycle() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root)
        var archived = ChatThread(title: "Archived", messages: [
            .init(role: .user, content: "old task")
        ])
        archived.isArchived = true
        let active = ChatThread(title: "Active", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "quill")
        ])
        try threadStore.save(archived)
        try threadStore.save(active)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [archived, active],
                selectedThreadID: active.id
            ),
            threadStore: threadStore
        )

        XCTAssertTrue(model.renameThread(active.id, to: "Renamed Active"))
        XCTAssertEqual(model.selectedThread?.title, "Renamed Active")
        XCTAssertEqual(try threadStore.load(active.id).title, "Renamed Active")

        let duplicateID = try XCTUnwrap(model.duplicateThread(active.id))
        let duplicate = try threadStore.load(duplicateID)
        XCTAssertEqual(duplicate.title, "Copy: Renamed Active")
        XCTAssertEqual(duplicate.messages.map(\.content), ["run whoami", "quill"])
        XCTAssertEqual(duplicate.events.last?.summary, "Duplicated from Renamed Active")
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)

        XCTAssertTrue(model.unarchiveThread(archived.id))
        XCTAssertEqual(model.root.selectedThreadID, archived.id)
        XCTAssertFalse(try threadStore.load(archived.id).isArchived)
        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Archived", "Copy: Renamed Active", "Renamed Active"])

        XCTAssertTrue(model.deleteThread(archived.id))
        XCTAssertThrowsError(try threadStore.load(archived.id))
        XCTAssertFalse(model.root.threads.contains { $0.id == archived.id })
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)
    }

    func testModeAndModelUpdateSelectedThreadAndTopBar() {
        let thread = ChatThread()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.setMode(.review)
        model.setModel("provider/model")

        XCTAssertEqual(model.selectedThread?.mode, .review)
        XCTAssertEqual(model.selectedThread?.model, "provider/model")
        XCTAssertEqual(model.root.topBar.mode, .review)
        XCTAssertEqual(model.root.topBar.model, "provider/model")
    }

    func testToggleModelFavoriteUpdatesConfigAndSurface() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(favoriteModels: ["provider/old"]),
            topBar: TopBarState(model: TrustedRouterDefaults.fusionModel),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        model.toggleModelFavorite(" z-ai/glm-5.2 ")

        XCTAssertEqual(model.root.config.favoriteModels, ["provider/old", "z-ai/glm-5.2"])
        XCTAssertEqual(model.surface().topBar.modelCategories.first?.category, "Favorites")
        XCTAssertEqual(model.surface().topBar.modelCategories.first?.models.map(\.id), ["provider/old", "z-ai/glm-5.2"])

        model.toggleModelFavorite("provider/old")

        XCTAssertEqual(model.root.config.favoriteModels, ["z-ai/glm-5.2"])
        XCTAssertEqual(model.surface().topBar.modelCategories.first?.models.map(\.id), ["z-ai/glm-5.2"])
    }

    func testApplySettingsUpdatesConfigThreadAndSettingsSurface() {
        let thread = ChatThread()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let config = AppConfig(
            defaultModel: "z-ai/glm-5.2",
            mode: .review,
            apiBaseURL: "https://api.trustedrouter.test/v1",
            developerOverrideEnabled: true
        )

        model.applySettings(config: config, trustedRouterAPIKeyConfigured: true)

        XCTAssertEqual(model.root.config, config)
        XCTAssertEqual(model.selectedThread?.mode, .review)
        XCTAssertEqual(model.selectedThread?.model, "z-ai/glm-5.2")
        XCTAssertEqual(model.surface().settings.apiBaseURL, "https://api.trustedrouter.test/v1")
        XCTAssertTrue(model.surface().settings.developerOverrideEnabled)
        XCTAssertTrue(model.surface().settings.hasStoredAPIKey)
        XCTAssertEqual(model.surface().settings.apiKeyStatusLabel, "API key configured")
    }

    func testApplyRuntimeRefreshesAgentStatus() {
        let model = QuillCodeWorkspaceModel()

        model.applyRuntime(QuillCodeRuntime(
            runner: AgentRunner(),
            mode: .trustedRouter,
            statusLabel: "TrustedRouter ready"
        ))

        XCTAssertEqual(model.root.topBar.agentStatus, "TrustedRouter ready")
    }

    func testRuntimeIssueSurfacesMissingTrustedRouterSignIn() {
        let model = QuillCodeWorkspaceModel()

        model.applyRuntime(QuillCodeRuntime(
            runner: AgentRunner(),
            mode: .trustedRouter,
            statusLabel: "Sign in with TrustedRouter"
        ))

        let surface = model.surface()
        XCTAssertEqual(surface.runtimeIssue?.severity, .warning)
        XCTAssertEqual(surface.runtimeIssue?.title, "TrustedRouter sign-in needed")
        XCTAssertEqual(surface.runtimeIssue?.actionLabel, "Open Settings")
        XCTAssertEqual(surface.topBar.runtimeIssueLabel, "TrustedRouter sign-in needed")
        XCTAssertEqual(surface.topBar.runtimeIssueSeverity, .warning)
        XCTAssertEqual(surface.settings.runtimeIssue?.title, "TrustedRouter sign-in needed")
    }

    func testRuntimeIssueNormalizesRejectedTrustedRouterKey() throws {
        let model = QuillCodeWorkspaceModel()

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter OAuth exchange failed with HTTP 401: Invalid API key"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.title, "TrustedRouter key rejected")
        XCTAssertEqual(issue.actionLabel, "Fix key")
        XCTAssertTrue(issue.message.contains("Sign in again"))
    }

    func testRuntimeIssueNormalizesMalformedModelAction() throws {
        let model = QuillCodeWorkspaceModel()

        model.setAgentStatus(
            "Failed",
            lastError: "Expected valid QuillCode action JSON but received an empty argument object."
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "Model response was malformed")
        XCTAssertEqual(issue.actionLabel, "Switch model")
    }

    func testRuntimeIssueNormalizesTrustedRouterRateLimit() throws {
        let config = AppConfig(
            defaultModel: TrustedRouterDefaults.fusionModel,
            apiBaseURL: "https://api.trustedrouter.test/v1"
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            topBar: TopBarState(model: TrustedRouterDefaults.fusionModel),
            trustedRouterAPIKeyConfigured: true
        ))

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter request failed with HTTP 429: Rate limit exceeded. Retry-After: 120. x-ratelimit-remaining: 0"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "TrustedRouter rate limit reached")
        XCTAssertEqual(issue.actionLabel, "Switch model")
        XCTAssertTrue(issue.message.contains("switch models"))

        let diagnostics = Dictionary(uniqueKeysWithValues: issue.diagnostics.map { ($0.label, $0.value) })
        XCTAssertEqual(diagnostics["Provider status"], "Rate limited")
        XCTAssertEqual(diagnostics["Retry after"], "120s")
        XCTAssertEqual(diagnostics["Rate limit remaining"], "0")
        XCTAssertEqual(diagnostics["Last error"], "TrustedRouter request failed with HTTP 429: Rate limit exceeded. Retry-After: 120. x-ratelimit-remaining: 0")
    }

    func testRuntimeIssueIncludesRedactedDiagnostics() throws {
        let config = AppConfig(
            defaultModel: "z-ai/glm-5.2",
            apiBaseURL: "https://api.trustedrouter.test/v1",
            developerOverrideEnabled: true
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            topBar: TopBarState(model: "z-ai/glm-5.2"),
            trustedRouterAPIKeyConfigured: true
        ))

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter request timed out with Bearer sk-tr-v1-superSecretDiagnosticKey"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        let diagnostics = Dictionary(uniqueKeysWithValues: issue.diagnostics.map { ($0.label, $0.value) })
        XCTAssertEqual(diagnostics["API base URL"], "https://api.trustedrouter.test/v1")
        XCTAssertEqual(diagnostics["Authentication"], "Developer override")
        XCTAssertEqual(diagnostics["Key state"], "Configured")
        XCTAssertEqual(diagnostics["Model"], "z-ai/glm-5.2")
        XCTAssertEqual(diagnostics["Agent status"], "Failed")
        XCTAssertTrue(diagnostics["Last error"]?.contains("Bearer ...redacted") == true)
        XCTAssertFalse(diagnostics["Last error"]?.contains("superSecretDiagnosticKey") == true)
        XCTAssertEqual(model.surface().settings.runtimeIssue?.diagnostics, issue.diagnostics)
    }

    func testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError() throws {
        let thread = ChatThread(messages: [
            ChatMessage(role: .user, content: "run whoami"),
            ChatMessage(role: .assistant, content: "Network failed."),
            ChatMessage(role: .user, content: "run pwd")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.setAgentStatus("Failed", lastError: "Network is unreachable")

        XCTAssertTrue(model.prepareRetryLastUserTurn())

        XCTAssertEqual(model.composer.draft, "run pwd")
        XCTAssertNil(model.lastError)
        XCTAssertNil(model.surface().runtimeIssue)
    }

    func testRetryLastTurnCommandReflectsTranscriptAvailability() throws {
        let emptyModel = QuillCodeWorkspaceModel()
        let emptyRetry = try XCTUnwrap(emptyModel.surface().commands.first { $0.id == "retry-last-turn" })
        XCTAssertFalse(emptyRetry.isEnabled)

        let thread = ChatThread(messages: [
            ChatMessage(role: .assistant, content: "I can help."),
            ChatMessage(role: .user, content: "run whoami")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let retry = try XCTUnwrap(model.surface().commands.first { $0.id == "retry-last-turn" })
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(retry.category, WorkspaceCommandPalette.controlCategory)
    }

    func testToolCardsRepresentSafetyReview() {
        let event = ThreadEvent(kind: .approvalRequested, summary: "clarify: needs target")
        let thread = ChatThread(events: [event])

        let cards = QuillCodeWorkspaceModel.toolCards(for: thread)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "Safety Check")
        XCTAssertEqual(cards[0].status, .review)
        XCTAssertTrue(cards[0].isExpanded)
        XCTAssertEqual(cards[0].density, .expanded)
    }

    func testToolCardsRepresentStoppedActiveToolAsFailed() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "sleep 10"])
        )
        let callJSON = try JSONHelpers.encodePretty(call)
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(
                kind: .toolFailed,
                summary: "Stopped by user",
                payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#
            ),
            ThreadEvent(kind: .notice, summary: "Stopped by user")
        ])

        let cards = QuillCodeWorkspaceModel.toolCards(for: thread)
        let timeline = QuillCodeWorkspaceModel.transcriptTimelineItems(for: thread)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].status, .failed)
        XCTAssertEqual(cards[0].subtitle, "Failed")
        XCTAssertEqual(cards[0].density, .expanded)
        XCTAssertEqual(cards[0].outputJSON, #"{"ok":false,"error":"Stopped by user"}"#)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.status, .failed)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.density, .expanded)
    }

    func testBootstrapLoadsConfigAndPersistedThreads() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        try ConfigStore(fileURL: paths.configFile).save(AppConfig(
            defaultModel: "trustedrouter/glm-5.2",
            mode: .review
        ))
        let project = ProjectRef(name: "QuillCode", path: root.path)
        try JSONProjectStore(fileURL: paths.projectsFile).save([project])
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        let older = ChatThread(
            title: "Older",
            projectID: project.id,
            mode: .review,
            model: "trustedrouter/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ChatThread(
            title: "Newer",
            projectID: project.id,
            mode: .review,
            model: "trustedrouter/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        try store.save(older)
        try store.save(newer)
        try JSONAutomationStore(fileURL: paths.automationsFile).save([
            QuillAutomation(
                title: "Ship follow-up",
                detail: "Check whether the release branch is ready.",
                kind: .threadFollowUp,
                scheduleKind: .heartbeat,
                scheduleDescription: "Tomorrow at 9:00 AM",
                projectID: project.id,
                threadID: newer.id,
                nextRunAt: Date(timeIntervalSince1970: 10)
            )
        ])

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.config.defaultModel, "trustedrouter/glm-5.2")
        XCTAssertEqual(model.root.config.mode, .review)
        XCTAssertEqual(model.root.projects.map(\.name), ["QuillCode"])
        XCTAssertEqual(model.root.selectedProjectID, project.id)
        XCTAssertEqual(model.root.threads.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(model.root.selectedThreadID, newer.id)
        XCTAssertEqual(model.surface().topBar.primaryTitle, "Newer")
        XCTAssertEqual(model.surface().topBar.subtitle, "QuillCode - Review - trustedrouter/glm-5.2")
        XCTAssertEqual(model.surface().automations.statusLabel, "1 active")
        XCTAssertEqual(model.surface().automations.workflows.map(\.title), ["Ship follow-up"])
        XCTAssertEqual(model.surface().automations.workflows.first?.scheduleLabel, "Tomorrow at 9:00 AM")

        let nextConfig = AppConfig(defaultModel: TrustedRouterDefaults.fusionModel, mode: .auto)
        try QuillCodeWorkspaceBootstrap(paths: paths).saveConfig(nextConfig)
        XCTAssertEqual(try ConfigStore(fileURL: paths.configFile).load(), nextConfig)
    }

    func testModelPersistsProjectRegistryChanges() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let model = QuillCodeWorkspaceModel(projectStore: projectStore)

        _ = model.addProject(path: root, name: "QuillCode")

        XCTAssertEqual(try projectStore.load().map(\.name), ["QuillCode"])
    }

    func testModelPersistsAutomationChanges() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let automationStore = JSONAutomationStore(fileURL: paths.automationsFile)
        let model = QuillCodeWorkspaceModel(automationStore: automationStore)

        model.setAutomations([
            QuillAutomation(
                title: "Morning check",
                detail: "Summarize the repo state.",
                kind: .workspaceSchedule,
                scheduleKind: .cron,
                scheduleDescription: "Every morning"
            )
        ])

        XCTAssertEqual(try automationStore.load().map(\.title), ["Morning check"])
    }

    func testAutomationCommandsCreatePauseResumeAndDeletePersistedFollowUp() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let automationStore = JSONAutomationStore(fileURL: paths.automationsFile)
        let thread = ChatThread(title: "Launch plan")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            automationStore: automationStore
        )

        XCTAssertTrue(model.runWorkspaceCommand("automation-create-thread-follow-up", workspaceRoot: root))

        let created = try XCTUnwrap(try automationStore.load().first)
        XCTAssertEqual(created.title, "Follow up: Launch plan")
        XCTAssertEqual(created.threadID, thread.id)
        XCTAssertEqual(created.status, .active)
        XCTAssertEqual(model.surface().automations.statusLabel, "1 active")

        XCTAssertTrue(model.runWorkspaceCommand("automation-pause:\(created.id.uuidString)", workspaceRoot: root))
        XCTAssertEqual(try automationStore.load().first?.status, .paused)
        XCTAssertEqual(model.surface().automations.workflows.first?.primaryActionTitle, "Resume")

        XCTAssertTrue(model.runWorkspaceCommand("automation-resume:\(created.id.uuidString)", workspaceRoot: root))
        XCTAssertEqual(try automationStore.load().first?.status, .active)
        XCTAssertEqual(model.surface().automations.workflows.first?.primaryActionTitle, "Pause")

        XCTAssertTrue(model.runWorkspaceCommand("automation-delete:\(created.id.uuidString)", workspaceRoot: root))
        XCTAssertEqual(try automationStore.load(), [])
        XCTAssertEqual(model.surface().automations.workflows.map(\.title), [
            "Thread follow-ups",
            "Workspace schedules",
            "Monitors"
        ])
    }

    func testBootstrapPersistsAndClearsTrustedRouterAPIKey() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        let bootstrap = QuillCodeWorkspaceBootstrap(paths: paths)

        XCTAssertFalse(bootstrap.hasTrustedRouterAPIKey())
        try bootstrap.saveTrustedRouterAPIKey("  sk-tr-v1-test  ")
        XCTAssertTrue(bootstrap.hasTrustedRouterAPIKey())

        let model = try bootstrap.makeModel()
        XCTAssertTrue(model.surface().settings.hasStoredAPIKey)

        try bootstrap.clearTrustedRouterAPIKey()
        XCTAssertFalse(bootstrap.hasTrustedRouterAPIKey())
    }

    func testRuntimeFactoryUsesTrustedRouterWhenEnvironmentKeyExists() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()

        let runtime = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["TRUSTEDROUTER_API_KEY": "sk-test"]
        ).makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .trustedRouter)
        XCTAssertEqual(runtime.statusLabel, "TrustedRouter signed in")
    }

    func testRuntimeFactoryUsesTrustedRouterWhenSecretExists() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        try FileSecretStore(directory: paths.secretsDirectory).write(
            "sk-test",
            for: QuillSecretKeys.trustedRouterAPIKey
        )

        let runtime = QuillCodeRuntimeFactory(paths: paths, environment: [:])
            .makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .trustedRouter)
    }

    func testRuntimeFactoryCanForceMockForDeterministicRuns() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()

        let runtime = QuillCodeRuntimeFactory(
            paths: paths,
            environment: [
                "TRUSTEDROUTER_API_KEY": "sk-test",
                "QUILLCODE_USE_MOCK_LLM": "true"
            ]
        ).makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .mock)
        XCTAssertEqual(runtime.statusLabel, "Mock LLM")
    }

    func testRunReviewStageActionStagesFileAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        try "old\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        try "new\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let thread = ChatThread(title: "Review")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .stage, path: "hello.txt"),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            "host.git.stage",
            "host.git.diff"
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertFalse(model.surface().review.isVisible)
        XCTAssertEqual(try runGit(["status", "--short"], cwd: root), "M  hello.txt\n")
    }

    func testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        try "old\n".write(
            to: remoteRoot.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try runGit(["add", "hello.txt"], cwd: remoteRoot)
        _ = try runGit(["commit", "-m", "add hello"], cwd: remoteRoot)
        try "new\n".write(
            to: remoteRoot.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )
        let argumentsFile = root.appendingPathComponent("ssh-review-stage-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let thread = ChatThread(title: "Remote Review", projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .stage, path: "hello.txt"),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        let cards = model.currentToolCards
        XCTAssertEqual(cards.map(\.title), [
            ToolDefinition.gitStage.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertEqual(cards.map(\.executionContext?.kind), [ExecutionContextKind.sshRemote, .sshRemote])
        XCTAssertTrue(cards.allSatisfy { $0.status == ToolCardStatus.done })
        XCTAssertEqual(try runGit(["status", "--short"], cwd: remoteRoot), "M  hello.txt\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("git diff"), arguments)
    }

    func testAddReviewCommentAppendsThreadEventForVisibleDiffFile() throws {
        let diff = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1,2 @@
        +new
         old
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let thread = ChatThread(
            title: "Review",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertTrue(model.addReviewComment(path: "hello.txt", text: "Keep this wording direct."))
        XCTAssertTrue(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            lineKind: .insertion,
            text: "Check the new line."
        ))
        XCTAssertTrue(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            endLineNumber: 2,
            lineKind: nil,
            text: "Keep these lines together."
        ))
        XCTAssertFalse(model.addReviewComment(path: "README.md", text: "Stale file"))
        XCTAssertFalse(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            endLineNumber: 4,
            lineKind: nil,
            text: "Invalid range"
        ))

        XCTAssertEqual(model.selectedThread?.events.filter { $0.kind == .reviewComment }.count, 3)
        XCTAssertEqual(model.surface().review.files.first?.comments.map(\.text), ["Keep this wording direct."])
        XCTAssertEqual(
            model.surface().review.files.first?.hunkItems.first?.lines.first?.comments.map(\.text),
            ["Check the new line.", "Keep these lines together."]
        )
        XCTAssertEqual(
            model.surface().review.files.first?.hunkItems.first?.lines.first?.comments.last?.lineRangeLabel,
            "Lines 1-2"
        )
    }

    func testRunReviewRestoreActionRestoresFileAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let fileURL = root.appendingPathComponent("hello.txt")
        try "old\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        try "new\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let thread = ChatThread(title: "Review")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .restore, path: "hello.txt"),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            "host.git.restore",
            "host.git.diff"
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "old\n")
        XCTAssertEqual(try runGit(["status", "--short"], cwd: root), "")
        XCTAssertFalse(model.surface().review.isVisible)
    }

    func testRemoteProjectReviewRestoreActionRunsThroughSSHAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let remoteFileURL = remoteRoot.appendingPathComponent("hello.txt")
        try "old\n".write(to: remoteFileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: remoteRoot)
        _ = try runGit(["commit", "-m", "add hello"], cwd: remoteRoot)
        try "new\n".write(to: remoteFileURL, atomically: true, encoding: .utf8)
        let argumentsFile = root.appendingPathComponent("ssh-review-restore-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let thread = ChatThread(title: "Remote Review", projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .restore, path: "hello.txt"),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        let cards = model.currentToolCards
        XCTAssertEqual(cards.map(\.title), [
            ToolDefinition.gitRestore.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertEqual(cards.map(\.executionContext?.kind), [ExecutionContextKind.sshRemote, .sshRemote])
        XCTAssertTrue(cards.allSatisfy { $0.status == ToolCardStatus.done })
        XCTAssertEqual(try String(contentsOf: remoteFileURL, encoding: .utf8), "old\n")
        XCTAssertEqual(try runGit(["status", "--short"], cwd: remoteRoot), "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("git diff"), arguments)
    }

    func testRunReviewStageHunkActionStagesPatchAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let fileURL = root.appendingPathComponent("hello.txt")
        try "one\ntwo\nthree\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        try "one\nTWO\nthree\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """
        let thread = ChatThread(title: "Review")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.runReviewAction(
            WorkspaceReviewActionSurface(
                kind: .stageHunk,
                path: "hello.txt",
                patch: patch,
                targetID: "hello.txt:hunk-1"
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            "host.git.stage_hunk",
            "host.git.diff"
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertTrue(try runGit(["diff", "--staged"], cwd: root).contains("+TWO"))
        XCTAssertFalse(model.surface().review.isVisible)
    }

    func testRemoteProjectReviewStageHunkActionRunsThroughSSHAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let remoteFileURL = remoteRoot.appendingPathComponent("hello.txt")
        try "one\ntwo\nthree\n".write(to: remoteFileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: remoteRoot)
        _ = try runGit(["commit", "-m", "add hello"], cwd: remoteRoot)
        try "one\nTWO\nthree\n".write(to: remoteFileURL, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """
        let argumentsFile = root.appendingPathComponent("ssh-review-stage-hunk-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let thread = ChatThread(title: "Remote Review", projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        model.runReviewAction(
            WorkspaceReviewActionSurface(
                kind: .stageHunk,
                path: "hello.txt",
                patch: patch,
                targetID: "hello.txt:hunk-1"
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        let cards = model.currentToolCards
        XCTAssertEqual(cards.map(\.title), [
            ToolDefinition.gitStageHunk.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertEqual(cards.map(\.executionContext?.kind), [ExecutionContextKind.sshRemote, .sshRemote])
        XCTAssertTrue(cards.allSatisfy { $0.status == ToolCardStatus.done })
        XCTAssertTrue(try runGit(["diff", "--staged"], cwd: remoteRoot).contains("+TWO"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("git diff"), arguments)
    }

    func testRuntimeFactoryModelCatalogFallsBackWithoutKey() async throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()

        let catalog = await QuillCodeRuntimeFactory(paths: paths, environment: [:])
            .fetchModelCatalog(config: AppConfig())

        XCTAssertEqual(catalog.defaultModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertTrue(catalog.models.contains { $0.id == "trustedrouter/fast" })
        XCTAssertTrue(catalog.models.contains { $0.id == TrustedRouterDefaults.fusionModel })
        XCTAssertTrue(catalog.models.contains { $0.id == "z-ai/glm-5.2" })
    }

    func testPlanUpdateToolRecordsNormalizedActivityPlan() throws {
        let model = QuillCodeWorkspaceModel(activity: ActivityState(isVisible: true))
        _ = model.newChat()
        let update = AgentPlanUpdate(
            explanation: "  Keep the plan visible while work proceeds.  ",
            plan: [
                AgentPlanItem(step: "  Inspect state  ", status: .completed),
                AgentPlanItem(step: "Implement change", status: .inProgress, detail: "  One reviewable slice.  "),
                AgentPlanItem(step: "Validate and summarize", status: .pending)
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())
        let decoded = try JSONHelpers.decode(AgentPlanUpdate.self, from: result.stdout)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(decoded.explanation, "Keep the plan visible while work proceeds.")
        XCTAssertEqual(decoded.plan.map(\.step), ["Inspect state", "Implement change", "Validate and summarize"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "\(ToolDefinition.planUpdate.name) completed")
        XCTAssertEqual(model.surface().activity.planItems.map(\.title), [
            "Inspect state",
            "Implement change",
            "Validate and summarize"
        ])
        XCTAssertEqual(model.surface().activity.planItems.map(\.statusLabel), ["Done", "Running", "Pending"])
        XCTAssertEqual(model.surface().activity.planItems[1].detail, "One reviewable slice.")
    }

    func testPlanUpdateToolRejectsMultipleRunningSteps() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        let update = AgentPlanUpdate(
            plan: [
                AgentPlanItem(step: "First", status: .inProgress),
                AgentPlanItem(step: "Second", status: .inProgress)
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Plan update can have at most one in_progress step.")
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFakeSSH(in root: URL, argumentsFile: URL) throws -> URL {
        let script = root.appendingPathComponent("fake-ssh")
        let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsPath)'
        echo 'remote-terminal'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func makeExecutingFakeSSH(in root: URL, argumentsFile: URL) throws -> URL {
        let script = root.appendingPathComponent("fake-executing-ssh")
        let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        : > '\(argumentsPath)'
        last=''
        for arg in "$@"; do
          printf '%s\\n' "$arg" >> '\(argumentsPath)'
          last="$arg"
        done
        /bin/sh -lc "$last"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func initializeGitRepository(at root: URL) throws {
        _ = try runGit(["init"], cwd: root)
        _ = try runGit(["config", "user.email", "quillcode-tests@example.com"], cwd: root)
        _ = try runGit(["config", "user.name", "QuillCode Tests"], cwd: root)
    }

    private func makeTempGitRepoWithInitialCommit() throws -> URL {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepository(at: root)
        try "# Test repo\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "README.md"], cwd: root)
        _ = try runGit(["commit", "-m", "initial"], cwd: root)
        return root
    }

    private func writeFixtureMCPServer(
        in root: URL,
        callText: String? = nil,
        includeResourcesAndPrompts: Bool = false,
        resourceText: String? = nil,
        promptText: String? = nil
    ) throws -> URL {
        let script = root.appendingPathComponent("fixture-mcp.sh")
        let capabilities = includeResourcesAndPrompts
            ? #""capabilities":{"tools":{},"resources":{},"prompts":{}}"#
            : #""capabilities":{"tools":{}}"#
        let resourceAndPromptResponses = includeResourcesAndPrompts
            ? """
        emit '{"jsonrpc":"2.0","id":3,"result":{"resources":[{"name":"README","uri":"file:///workspace/README.md"},{"name":"Project config","uri":"file:///workspace/.quillcode/config.toml"}]}}'
        emit '{"jsonrpc":"2.0","id":4,"result":{"prompts":[{"name":"summarize_project"}]}}'
        """
            : ""
        let callResponseID = includeResourcesAndPrompts ? 5 : 3
        let callResponse = resourceText.map {
            "emit '{\"jsonrpc\":\"2.0\",\"id\":\(callResponseID),\"result\":{\"contents\":[{\"uri\":\"file:///workspace/README.md\",\"mimeType\":\"text/markdown\",\"text\":\"\($0)\"}]}}'"
        } ?? promptText.map {
            "emit '{\"jsonrpc\":\"2.0\",\"id\":\(callResponseID),\"result\":{\"description\":\"Summarize the project.\",\"messages\":[{\"role\":\"user\",\"content\":{\"type\":\"text\",\"text\":\"\($0)\"}}]}}'"
        } ?? callText.map {
            "emit '{\"jsonrpc\":\"2.0\",\"id\":\(callResponseID),\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"\($0)\"}],\"isError\":false}}'"
        } ?? ""
        let content = """
        #!/bin/sh
        emit() {
          body="$1"
          length=$(printf "%s" "$body" | wc -c | tr -d ' ')
          printf "Content-Length: %s\\r\\n\\r\\n%s" "$length" "$body"
        }
        emit '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"Fixture MCP","version":"1.0.0"},\(capabilities)}}'
        emit '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"read_file","description":"Read a file","inputSchema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},{"name":"write_file","inputSchema":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"},"overwrite":{"type":"boolean"}},"required":["path","content"]}}]}}'
        \(resourceAndPromptResponses)
        \(callResponse)
        sleep 60
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func runGit(_ arguments: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "QuillCodeAppTests.Git",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? out : err]
            )
        }
        return out
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private struct SlowLLMClient: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return .say("late response")
    }
}

private enum DelayedStreamingSayLLMError: Error {
    case nonStreamingPathUsed
}

private struct DelayedStreamingSayLLMClient: StreamingLLMClient {
    var chunks: [String]

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw DelayedStreamingSayLLMError.nonStreamingPathUsed
    }

    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    for (index, chunk) in chunks.enumerated() {
                        continuation.yield(chunk)
                        if index < chunks.count - 1 {
                            try await Task.sleep(nanoseconds: 150_000_000)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct ImmediateToolLLMClient: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "pwd"])
        ))
    }
}

private struct FixedToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}

private final class ToolDefinitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedTools: [ToolDefinition] = []

    var tools: [ToolDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTools
    }

    func record(_ tools: [ToolDefinition]) {
        lock.lock()
        recordedTools = tools
        lock.unlock()
    }
}

private struct RecordingLLMClient: LLMClient {
    var recorder: ToolDefinitionRecorder

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        recorder.record(tools)
        return .say("Recorded tool definitions.")
    }
}

private struct SlowApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        try? await Task.sleep(nanoseconds: 200_000_000)
        return SafetyReview(
            verdict: .approve,
            rationale: "The tool call is bounded and matches the current user request.",
            userIntentMatched: true
        )
    }
}
