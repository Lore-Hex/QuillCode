import XCTest
import QuillCodeAgent
import QuillCodePersistence
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceProjectIntegrationTests: XCTestCase {
    func testTypedSSHProjectRegistrationSelectsAndPersistsRemote() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let model = QuillCodeWorkspaceModel(projectStore: projectStore)
        let connection = ProjectConnection.ssh(path: "/srv/app", host: "production")

        let projectID = try XCTUnwrap(model.addSSHProject(connection: connection, name: "Remote App"))

        XCTAssertEqual(model.root.selectedProjectID, projectID)
        XCTAssertEqual(model.selectedProject?.connection, connection)
        XCTAssertEqual(try projectStore.load().first?.connection, connection)
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

    func testProjectReorderCommandsMoveSelectedProject() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        let alpha = model.addProject(path: root.appendingPathComponent("Alpha"), name: "Alpha")
        model.addProject(path: root.appendingPathComponent("Beta"), name: "Beta")
        let gamma = model.addProject(path: root.appendingPathComponent("Gamma"), name: "Gamma")

        XCTAssertEqual(projectNames(in: model), ["Gamma", "Beta", "Alpha"])

        model.selectProject(gamma)
        XCTAssertTrue(model.runWorkspaceCommand("project-move-down", workspaceRoot: root))
        XCTAssertEqual(projectNames(in: model), ["Beta", "Gamma", "Alpha"])

        XCTAssertTrue(model.runWorkspaceCommand("project-move-up", workspaceRoot: root))
        XCTAssertEqual(projectNames(in: model), ["Gamma", "Beta", "Alpha"])

        model.selectProject(alpha)
        XCTAssertTrue(model.runWorkspaceCommand("project-move-to-top", workspaceRoot: root))
        XCTAssertEqual(projectNames(in: model), ["Alpha", "Gamma", "Beta"])
        XCTAssertTrue(model.runWorkspaceCommand("project-move-to-bottom", workspaceRoot: root))
        XCTAssertEqual(projectNames(in: model), ["Gamma", "Beta", "Alpha"])
        XCTAssertFalse(model.runWorkspaceCommand("project-move-to-bottom", workspaceRoot: root))
        XCTAssertFalse(model.runWorkspaceCommand("project-move-down", workspaceRoot: root))

        XCTAssertTrue(model.moveProject(alpha, before: gamma))
        XCTAssertEqual(projectNames(in: model), ["Alpha", "Gamma", "Beta"])
        XCTAssertFalse(model.moveProject(alpha, before: gamma))
        XCTAssertEqual(model.root.selectedProjectID, alpha)
    }

    func testProjectInstructionsLoadIntoNewThreadsAndRefreshAfterRunStarts() async throws {
        let root = try makeQuillCodeTestDirectory()
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
        await model.waitForScheduledProjectContextRefresh()

        XCTAssertTrue(model.selectedThread?.instructions.first?.content.contains("targeted unit tests") == true)
    }

    func testAgentSendCompletesWhileProjectContextLoaderIsStalled() async throws {
        let root = try makeQuillCodeTestDirectory()
        let projectID = UUID()
        let threadID = UUID()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [ProjectRef(id: projectID, name: "Slow Project", path: root.path)],
            selectedProjectID: projectID,
            threads: [ChatThread(id: threadID, projectID: projectID)],
            selectedThreadID: threadID
        ), runner: AgentRunner(llm: ImmediateProjectTestLLMClient()))
        let loaderGate = DispatchSemaphore(value: 0)
        model.projectMetadataLoader = { _, _ in
            loaderGate.wait()
            return WorkspaceProjectMetadata(
                instructions: [ProjectInstruction(
                    path: "AGENTS.md",
                    title: "Project AGENTS.md",
                    content: "Fresh agent context.",
                    byteCount: 20
                )],
                localActions: [],
                runHooks: [],
                extensionManifests: [],
                memories: []
            )
        }
        model.setDraft("inspect this project")

        let sendTask = Task { await model.submitComposer(workspaceRoot: root) }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while ContinuousClock.now < deadline,
              model.selectedThread?.messages.contains(where: { $0.content == "agent reached" }) != true {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.selectedThread?.messages.first?.content, "inspect this project")
        let completedWhileLoaderWasStalled = model.selectedThread?.messages.contains {
            $0.role == .assistant && $0.content == "agent reached"
        } == true
        loaderGate.signal()
        await sendTask.value
        await model.waitForScheduledProjectContextRefresh()

        XCTAssertTrue(completedWhileLoaderWasStalled)
        XCTAssertEqual(model.selectedThread?.instructions.first?.content, "Fresh agent context.")
    }

    func testScheduledProjectContextRefreshDoesNotBlockTheMainActor() async throws {
        let root = try makeQuillCodeTestDirectory()
        let projectID = UUID()
        let threadID = UUID()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [ProjectRef(name: "Slow Project", path: root.path)],
            selectedProjectID: projectID,
            threads: [ChatThread(id: threadID, projectID: projectID)],
            selectedThreadID: threadID
        ))
        model.root.projects[0].id = projectID
        model.projectMetadataLoader = { _, _ in
            Thread.sleep(forTimeInterval: 0.25)
            return WorkspaceProjectMetadata(
                instructions: [ProjectInstruction(
                    path: "AGENTS.md",
                    title: "Project AGENTS.md",
                    content: "Loaded away from the main actor.",
                    byteCount: 32
                )],
                localActions: [],
                runHooks: [],
                extensionManifests: [],
                memories: []
            )
        }
        var didPublish = false
        model.onProjectContextChanged = { didPublish = true }
        let startedAt = ContinuousClock.now

        model.scheduleSelectedProjectContextRefresh()

        XCTAssertLessThan(startedAt.duration(to: .now), .milliseconds(100))
        await model.waitForScheduledProjectContextRefresh()
        XCTAssertEqual(model.selectedProject?.instructions.first?.content, "Loaded away from the main actor.")
        XCTAssertEqual(model.selectedThread?.instructions.first?.content, "Loaded away from the main actor.")
        XCTAssertTrue(didPublish)
    }

    func testRegisterProjectReturnsBeforeContextLoadAndPublishesTheResult() async throws {
        let root = try makeQuillCodeTestDirectory()
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "Project AGENTS.md",
            content: "Loaded after project registration.",
            byteCount: 34
        )
        let probe = BlockingProjectMetadataLoader(metadata: WorkspaceProjectMetadata(
            instructions: [instruction],
            localActions: [],
            runHooks: [],
            extensionManifests: [],
            memories: []
        ))
        let model = QuillCodeWorkspaceModel()
        model.projectMetadataLoader = { _, _ in probe.load() }
        defer { probe.release.signal() }
        var didPublish = false
        model.onProjectContextChanged = { didPublish = true }
        let startedAt = ContinuousClock.now

        let projectID = model.registerProject(path: root, name: "Responsive Project")

        XCTAssertLessThan(startedAt.duration(to: .now), .milliseconds(100))
        XCTAssertEqual(model.root.selectedProjectID, projectID)
        XCTAssertEqual(model.selectedProject?.name, "Responsive Project")
        XCTAssertTrue(model.selectedProject?.instructions.isEmpty == true)

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline, probe.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(probe.callCount, 1)
        XCTAssertFalse(probe.loadedOnMainThread)

        probe.release.signal()
        await model.waitForScheduledProjectContextRefresh()

        XCTAssertEqual(model.selectedProject?.instructions, [instruction])
        XCTAssertTrue(didPublish)
    }

    func testRestoredProjectWorktreeEnvironmentsLoadOffMainAndRemainCached() async throws {
        let root = try makeQuillCodeTestDirectory()
        let configurationDirectory = root.appendingPathComponent(".quillcode")
        let configurationURL = configurationDirectory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true
        )
        try """
        [worktree_setup]
        default_environment = "development"

        [local_environments.development]
        title = "Development"
        """.write(to: configurationURL, atomically: true, encoding: .utf8)
        let projectID = UUID()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [ProjectRef(id: projectID, name: "Restored", path: root.path)],
            selectedProjectID: projectID
        ))

        XCTAssertTrue(model.surface().worktreeEnvironments.options.isEmpty)

        model.scheduleSelectedProjectContextRefresh()
        await model.waitForScheduledProjectContextRefresh()

        XCTAssertEqual(
            model.surface().worktreeEnvironments.options.map(\.title),
            ["Development"]
        )

        try """
        [worktree_setup]
        default_environment = "release"

        [local_environments.release]
        title = "Release"
        """.write(to: configurationURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(
            model.surface().worktreeEnvironments.options.map(\.title),
            ["Development"]
        )

        model.scheduleSelectedProjectContextRefresh()
        await model.waitForScheduledProjectContextRefresh()

        XCTAssertEqual(model.surface().worktreeEnvironments.options.map(\.title), ["Release"])
    }

    func testRepeatedScheduledProjectContextRefreshCoalescesAnInFlightScan() async throws {
        let root = try makeQuillCodeTestDirectory()
        let projectID = UUID()
        let probe = BlockingProjectMetadataLoader()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [ProjectRef(id: projectID, name: "Slow Project", path: root.path)],
            selectedProjectID: projectID
        ))
        model.projectMetadataLoader = { _, _ in probe.load() }

        model.scheduleSelectedProjectContextRefresh()
        model.scheduleSelectedProjectContextRefresh()
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline, probe.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        model.scheduleSelectedProjectContextRefresh()

        XCTAssertEqual(probe.callCount, 1)
        probe.release.signal()
        await model.waitForScheduledProjectContextRefresh()
        XCTAssertEqual(probe.callCount, 1)
    }

    func testScheduledProjectContextRefreshDropsAStaleSelectionResult() async throws {
        let firstRoot = try makeQuillCodeTestDirectory()
        let secondRoot = try makeQuillCodeTestDirectory()
        let firstID = UUID()
        let secondID = UUID()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [
                ProjectRef(id: firstID, name: "First", path: firstRoot.path),
                ProjectRef(id: secondID, name: "Second", path: secondRoot.path)
            ],
            selectedProjectID: firstID
        ))
        model.projectMetadataLoader = { root, _ in
            let isFirst = root == firstRoot.standardizedFileURL
            Thread.sleep(forTimeInterval: isFirst ? 0.25 : 0.01)
            let content = isFirst ? "Stale first context" : "Current second context"
            return WorkspaceProjectMetadata(
                instructions: [ProjectInstruction(
                    path: "AGENTS.md",
                    title: "Project AGENTS.md",
                    content: content,
                    byteCount: content.utf8.count
                )],
                localActions: [],
                runHooks: [],
                extensionManifests: [],
                memories: []
            )
        }

        model.scheduleSelectedProjectContextRefresh()
        model.root.selectedProjectID = secondID
        model.scheduleSelectedProjectContextRefresh()

        await model.waitForScheduledProjectContextRefresh()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(model.root.projects[0].instructions.isEmpty)
        XCTAssertEqual(model.root.projects[1].instructions.first?.content, "Current second context")
    }

    private func projectNames(in model: QuillCodeWorkspaceModel) -> [String] {
        model.surface().projects.items.map(\.name)
    }

    func testProjectMetadataRefreshPersistsResolvedInstructionDiagnostics() throws {
        let root = try makeQuillCodeTestDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode-store"))
        try paths.ensure()
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let featureDirectory = root.appendingPathComponent("Sources/Feature")
        try FileManager.default.createDirectory(at: featureDirectory, withIntermediateDirectories: true)
        try "Always run tests before finishing.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Do not run tests for feature changes.\n".write(
            to: featureDirectory.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let model = QuillCodeWorkspaceModel(projectStore: projectStore)
        let projectID = model.addProject(path: root, name: "Rules Project")
        let diagnosticID = try XCTUnwrap(
            ProjectInstructionDiagnosticsBuilder
                .diagnostics(for: model.root.projects[0].instructions)
                .first { $0.statusLabel == "conflict" }?
                .id
        )

        try "Always run focused tests before finishing.\n".write(
            to: featureDirectory.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        model.refreshProjectMetadata(projectID)

        let loaded = try XCTUnwrap(projectStore.load().first)
        XCTAssertEqual(loaded.resolvedInstructionDiagnosticIDs, [diagnosticID])
        XCTAssertEqual(loaded.dismissedInstructionDiagnosticIDs, [])
    }
}

private struct ImmediateProjectTestLLMClient: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say("agent reached")
    }
}

private final class BlockingProjectMetadataLoader: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let metadata: WorkspaceProjectMetadata
    private var calls = 0
    private var wasLoadedOnMainThread = false

    init(metadata: WorkspaceProjectMetadata = .empty) {
        self.metadata = metadata
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    var loadedOnMainThread: Bool {
        lock.withLock { wasLoadedOnMainThread }
    }

    func load() -> WorkspaceProjectMetadata {
        lock.withLock {
            calls += 1
            wasLoadedOnMainThread = Thread.isMainThread
        }
        release.wait()
        return metadata
    }
}
