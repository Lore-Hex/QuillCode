import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
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

    func testSlashCommandsRouteToWorkspaceActions() async throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Project")
        model.selectProject(projectID)

        model.setDraft("/terminal")
        await model.submitComposer(workspaceRoot: root)
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
        let timeline = QuillCodeWorkspaceModel.transcriptTimelineItems(for: thread)
        XCTAssertEqual(timeline.map(\.kind), [.message, .toolCard, .message])
        XCTAssertEqual(timeline[0].message?.role, .user)
        XCTAssertEqual(timeline[1].toolCard?.title, "host.shell.run")
        XCTAssertEqual(timeline[2].message?.role, .assistant)
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

    func testBrowserPreviewNormalizesURLsAndStoresComments() throws {
        let root = try makeTempDirectory()
        let previewFile = root.appendingPathComponent("preview.html")
        try "<h1>Preview</h1>".write(to: previewFile, atomically: true, encoding: .utf8)
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("toggle-browser", workspaceRoot: root))
        XCTAssertTrue(model.browser.isVisible)

        XCTAssertTrue(model.openBrowserPreview("localhost:3000", workspaceRoot: root))
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(model.browser.title, "localhost")
        XCTAssertEqual(model.browser.status, "Preview ready")

        XCTAssertTrue(model.openBrowserPreview("preview.html", workspaceRoot: root))
        XCTAssertEqual(model.browser.currentURL, previewFile.standardizedFileURL.resolvingSymlinksInPath().absoluteString)
        XCTAssertEqual(model.browser.title, "preview.html")

        XCTAssertTrue(model.addBrowserComment("Check the hero spacing"))
        XCTAssertEqual(model.browser.comments.count, 1)
        XCTAssertEqual(model.browser.comments[0].text, "Check the hero spacing")
        XCTAssertEqual(model.browser.comments[0].url, model.browser.currentURL)

        XCTAssertFalse(model.openBrowserPreview("not-a-valid-target", workspaceRoot: root))
        XCTAssertEqual(model.browser.status, "Invalid address")
        XCTAssertEqual(model.lastError, "Enter an http, https, file, localhost, or project file URL.")
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

    func testWorkspaceCreateAndRemoveWorktreeActionsRecordToolCards() throws {
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
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.create")
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
        XCTAssertTrue(model.currentToolCards.last?.inputJSON?.contains(worktreeName) == true)

        model.removeWorktree(.init(path: worktreeName), workspaceRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.remove")
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
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

    func testLocalEnvironmentActionLoaderBoundsScriptsAndRejectsSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory().appendingPathComponent("outside.sh")
        try "printf bad".write(to: outside, atomically: true, encoding: .utf8)
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
        try "printf two".write(
            to: actionsDirectory.appendingPathComponent("two.sh"),
            atomically: true,
            encoding: .utf8
        )

        let actions = LocalEnvironmentActionLoader.load(from: root, maxActions: 1)

        XCTAssertEqual(actions.map(\.relativePath), [".quillcode/actions/one.sh"])
        XCTAssertEqual(actions[0].command, #"sh '.quillcode/actions/one.sh'"#)
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
        XCTAssertTrue(message.contains("Model: trustedrouter/fusion"))
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

    func testToolCardsRepresentSafetyReview() {
        let event = ThreadEvent(kind: .approvalRequested, summary: "clarify: needs target")
        let thread = ChatThread(events: [event])

        let cards = QuillCodeWorkspaceModel.toolCards(for: thread)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "Safety Check")
        XCTAssertEqual(cards[0].status, .review)
        XCTAssertTrue(cards[0].isExpanded)
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

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.config.defaultModel, "trustedrouter/glm-5.2")
        XCTAssertEqual(model.root.config.mode, .review)
        XCTAssertEqual(model.root.projects.map(\.name), ["QuillCode"])
        XCTAssertEqual(model.root.selectedProjectID, project.id)
        XCTAssertEqual(model.root.threads.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(model.root.selectedThreadID, newer.id)
        XCTAssertEqual(model.surface().topBar.primaryTitle, "Newer")
        XCTAssertEqual(model.surface().topBar.subtitle, "QuillCode - Review - trustedrouter/glm-5.2")

        let nextConfig = AppConfig(defaultModel: "trustedrouter/fusion", mode: .auto)
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
        XCTAssertFalse(model.addReviewComment(path: "README.md", text: "Stale file"))

        XCTAssertEqual(model.selectedThread?.events.filter { $0.kind == .reviewComment }.count, 1)
        XCTAssertEqual(model.surface().review.files.first?.comments.map(\.text), ["Keep this wording direct."])
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

    func testRuntimeFactoryModelCatalogFallsBackWithoutKey() async throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()

        let catalog = await QuillCodeRuntimeFactory(paths: paths, environment: [:])
            .fetchModelCatalog(config: AppConfig())

        XCTAssertEqual(catalog.defaultModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertTrue(catalog.models.contains { $0.id == "trustedrouter/fusion" })
        XCTAssertTrue(catalog.models.contains { $0.id == "z-ai/glm-5.2" })
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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

private struct ImmediateToolLLMClient: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "pwd"])
        ))
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
