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

    func testEmptyDraftDoesNotCreateThread() async throws {
        let model = QuillCodeWorkspaceModel()
        model.setDraft("   ")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())
        XCTAssertTrue(model.root.threads.isEmpty)
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
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        let older = ChatThread(title: "Older", updatedAt: Date(timeIntervalSince1970: 1))
        let newer = ChatThread(title: "Newer", updatedAt: Date(timeIntervalSince1970: 2))
        try store.save(older)
        try store.save(newer)

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.config.defaultModel, "trustedrouter/glm-5.2")
        XCTAssertEqual(model.root.config.mode, .review)
        XCTAssertEqual(model.root.threads.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(model.root.selectedThreadID, newer.id)
        XCTAssertEqual(model.surface().topBar.primaryTitle, "Newer")

        let nextConfig = AppConfig(defaultModel: "trustedrouter/fusion", mode: .auto)
        try QuillCodeWorkspaceBootstrap(paths: paths).saveConfig(nextConfig)
        XCTAssertEqual(try ConfigStore(fileURL: paths.configFile).load(), nextConfig)
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
}
