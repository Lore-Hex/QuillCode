import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

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

    func testWorkspacePullRequestCommandsPrefillComposer() throws {
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
