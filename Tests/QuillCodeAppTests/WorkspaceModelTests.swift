import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceModelTests: XCTestCase {
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

    func testRemoteWorkspaceCommandListsGitWorktreesThroughSSH() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let argumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
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
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-list", workspaceRoot: root))

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitWorktreeList.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.stdout.contains(remoteRoot.standardizedFileURL.path), result.stdout)
        let sshArguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(sshArguments.contains("git worktree list --porcelain"), sshArguments)
    }

    func testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH() throws {
        let root = try makeTempDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let sshArgumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
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

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-view", workspaceRoot: root))
        var card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.artifacts.map(\.value), ["https://github.com/example/repo/pull/456"])
        var ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "view", "--comments"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checks", workspaceRoot: root))
        card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestChecks.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "checks"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-diff", workspaceRoot: root))
        card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestDiff.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "diff"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checkout", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Checkout pull request ")
    }

    func testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH() async throws {
        let root = try makeTempDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let sshArgumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        func ghArguments() throws -> [String] {
            try String(contentsOf: ghArgumentsFile, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
        }

        model.setDraft("/pr view 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(model.currentToolCards.last?.executionContext?.kind, .sshRemote)
        XCTAssertEqual(try ghArguments(), ["pr", "view", "456", "--comments"])

        model.setDraft("/pr checks 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestChecks.name)
        XCTAssertEqual(try ghArguments(), ["pr", "checks", "456"])

        model.setDraft("/pr diff 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestDiff.name)
        XCTAssertEqual(try ghArguments(), ["pr", "diff", "456"])

        model.setDraft("/pr checkout 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestCheckout.name)
        XCTAssertEqual(try ghArguments(), ["pr", "checkout", "456"])

        model.setDraft("/pr comment 456 ship it")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestComment.name)
        XCTAssertEqual(try ghArguments(), ["pr", "comment", "456", "--body", "ship it"])

        model.setDraft("/pr review approve 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestReview.name)
        XCTAssertEqual(try ghArguments(), ["pr", "review", "456", "--approve"])

        model.setDraft("/pr reviewers add alice bob")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestReviewers.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "--add-reviewer", "alice,bob"])

        model.setDraft("/pr labels add 456 merge-train, needs review")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "456", "--add-label", "merge-train,needs review"])

        model.setDraft("/pr labels remove stale")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "--remove-label", "stale"])

        model.setDraft("/pr merge 456 rebase auto delete-branch")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestMerge.name)
        XCTAssertEqual(try ghArguments(), ["pr", "merge", "456", "--rebase", "--auto", "--delete-branch"])
    }

    func testWorkspaceWorktreeCommandsPrefillComposer() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checkout", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Checkout pull request ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-reviewers", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Request reviewers for the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-comment", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Comment on the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-review", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Review the current pull request: approve")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-labels", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Label the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-merge", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Merge the current pull request with squash")

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
            WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards().contains { card in
                card.title == "host.git.worktree.create"
            }
        })
        XCTAssertNotEqual(createThread.id, model.selectedThread?.id)
        let createCard = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: createThread).toolCards().last)
        XCTAssertEqual(createCard.status, .done)
        XCTAssertTrue(createCard.inputJSON?.contains(worktreeName) == true)

        model.removeWorktree(.init(path: worktreeName), workspaceRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.remove")
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
    }

    func testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let parent = remoteRoot.deletingLastPathComponent()
        let worktreeName = "remote-ui-\(UUID().uuidString)"
        let branch = "remote-ui-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let argumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
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
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.createWorktree(.init(path: worktreeName, branch: String(branch)), workspaceRoot: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.selectedProject?.connection.kind, .ssh)
        XCTAssertEqual(model.selectedProject?.connection.host, "feather.local")
        XCTAssertEqual(model.selectedProject?.connection.user, "quill")
        XCTAssertEqual(model.selectedProject?.connection.port, 2222)
        XCTAssertEqual(model.selectedProject?.connection.path, worktree.path)
        XCTAssertEqual(model.selectedThread?.projectID, model.selectedProject?.id)
        XCTAssertEqual(model.selectedThread?.title, "Worktree: \(branch)")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Opened remote worktree `\(worktreeName)`") == true)
        XCTAssertEqual(model.root.topBar.projectName, "feather.local · \(worktreeName)")

        let createThread = try XCTUnwrap(model.root.threads.first { thread in
            WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards().contains { card in
                card.title == ToolDefinition.gitWorktreeCreate.name
            }
        })
        XCTAssertNotEqual(createThread.id, model.selectedThread?.id)
        let createCard = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: createThread).toolCards().last)
        XCTAssertEqual(createCard.status, .done)
        let createResult = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(createCard.outputJSON))
        XCTAssertEqual(createResult.artifacts, ["ssh://quill@feather.local:2222\(worktree.path)"])
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
            topBar: TopBarState(model: TrustedRouterDefaults.synthModel),
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

    func testToolCardsRepresentActionableApprovalReview() throws {
        let call = ToolCall(
            id: "approval-tool",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-request",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let event = ThreadEvent(
            kind: .approvalRequested,
            summary: "clarify: needs target",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )
        let thread = ChatThread(events: [event])

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, ToolDefinition.shellRun.name)
        XCTAssertEqual(cards[0].status, .review)
        XCTAssertTrue(cards[0].isExpanded)
        XCTAssertEqual(cards[0].density, .expanded)
        XCTAssertEqual(cards[0].reviewState, .ready)
        XCTAssertEqual(cards[0].inputJSON, ToolArguments.json(["cmd": "whoami"]))
        XCTAssertEqual(cards[0].actions.map(\.title), ["Run", "Skip"])
    }

    func testToolCardApprovalActionRecordsDecisionAndRunsTool() throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            id: "approval-tool-run",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-run",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let thread = ChatThread(events: [
            ThreadEvent(
                kind: .approvalRequested,
                summary: "review required",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let didRun = model.runToolCardAction(ToolCardActionSurface(
            title: "Run",
            kind: .approve,
            requestID: "approval-run",
            style: .primary
        ), workspaceRoot: root)

        XCTAssertTrue(didRun)
        let events = try XCTUnwrap(model.selectedThread?.events)
        XCTAssertTrue(events.contains { $0.kind == .approvalDecided })
        XCTAssertTrue(events.contains { $0.kind == .toolQueued })
        XCTAssertTrue(events.contains { $0.kind == .toolCompleted })
        let cards = model.currentToolCards
        XCTAssertTrue(cards.contains { $0.status == .done && $0.subtitle == "Approved · whoami" })
        XCTAssertTrue(cards.contains { $0.title == ToolDefinition.shellRun.name && $0.outputJSON?.contains("exitCode") == true })
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

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()
        let timeline = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].status, .failed)
        XCTAssertEqual(cards[0].subtitle, "Failed · sleep 10")
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

        let nextConfig = AppConfig(defaultModel: TrustedRouterDefaults.synthModel, mode: .auto)
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

}
