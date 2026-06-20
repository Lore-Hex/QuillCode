import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
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
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Output:") == true)

        let cards = model.currentToolCards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "host.shell.run")
        XCTAssertEqual(cards[0].status, .done)
        XCTAssertTrue(cards[0].inputJSON?.contains("whoami") == true)
        XCTAssertTrue(cards[0].outputJSON?.contains("\"ok\" : true") == true)
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

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a git worktree named ")

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-remove", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Remove git worktree at ")
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
        XCTAssertEqual(runtime.statusLabel, "TrustedRouter ready")
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
}
