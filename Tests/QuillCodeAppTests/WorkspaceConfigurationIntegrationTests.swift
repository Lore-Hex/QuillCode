import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceConfigurationIntegrationTests: XCTestCase {
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

    func testCycleModeAdvancesThroughTheFullRingAndWrapsBack() throws {
        let root = try makeQuillCodeTestDirectory()
        let thread = ChatThread(mode: .auto)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        // Auto → Plan → Review → Read-only → Auto (the Codex Shift+Tab ring), driven through the
        // real `cycle-mode` command id so the whole route (command → planner → executor) is covered.
        var seen: [AgentMode] = []
        for _ in 0..<AgentMode.cycleOrder.count {
            XCTAssertTrue(model.runWorkspaceCommand("cycle-mode", workspaceRoot: root))
            seen.append(try XCTUnwrap(model.selectedThread?.mode))
        }
        XCTAssertEqual(seen, [.plan, .review, .readOnly, .auto])
        XCTAssertEqual(model.root.topBar.mode, .auto)
    }

    func testFocusComposerCommandBumpsTheSurfaceFocusToken() throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [ChatThread()],
            selectedThreadID: nil
        ))
        _ = model.newChat()
        let before = model.surface().composer.focusToken

        // Driving the real command id bumps the token the view observes to grab focus.
        XCTAssertTrue(model.runWorkspaceCommand("focus-composer", workspaceRoot: root))
        XCTAssertEqual(model.surface().composer.focusToken, before + 1)
    }

    func testToggleModelFavoriteUpdatesConfigAndSurface() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(favoriteModels: ["provider/old"]),
            topBar: TopBarState(model: TrustedRouterDefaults.prometheusModel),
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
            developerOverrideEnabled: true,
            runSpendFuseUSD: 2,
            runSpendPeriodLimits: RunSpendPeriodLimits(dailyUSD: 5, weeklyUSD: 25, monthlyUSD: 100)
        )

        model.applySettings(config: config, trustedRouterAPIKeyConfigured: true)

        XCTAssertEqual(model.root.config, config)
        XCTAssertEqual(model.selectedThread?.mode, .review)
        XCTAssertEqual(model.selectedThread?.model, "z-ai/glm-5.2")
        XCTAssertEqual(model.surface().settings.apiBaseURL, "https://api.trustedrouter.test/v1")
        XCTAssertTrue(model.surface().settings.developerOverrideEnabled)
        XCTAssertTrue(model.surface().settings.hasStoredAPIKey)
        XCTAssertEqual(model.surface().settings.apiKeyStatusLabel, "API key configured")
        XCTAssertEqual(model.surface().settings.runSpendFuseUSD, 2)
        XCTAssertEqual(model.surface().settings.runSpendPeriodLimits.dailyUSD, 5)
        XCTAssertEqual(
            model.surface().topBar.tokenBudget?.visibleQuotaLimits.map(\.usageLabel),
            ["$0.00 / $5.00", "$0.00 / $25.00", "$0.00 / $100.00"]
        )
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

        let nextConfig = AppConfig(defaultModel: TrustedRouterDefaults.prometheusModel, mode: .auto)
        try QuillCodeWorkspaceBootstrap(paths: paths).saveConfig(nextConfig)
        XCTAssertEqual(try ConfigStore(fileURL: paths.configFile).load(), nextConfig)
    }

    func testBootstrapSurvivesACorruptThreadFileInsteadOfEmptyingTheSidebar() throws {
        // End-to-end regression pin: a single truncated thread file (crash-mid-write) used to make
        // threadStore.list() throw, aborting makeModel() and vanishing EVERY conversation. Bootstrap
        // must now surface the surviving threads.
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        try store.save(ChatThread(title: "Survivor A", updatedAt: Date(timeIntervalSince1970: 1)))
        try store.save(ChatThread(title: "Survivor B", updatedAt: Date(timeIntervalSince1970: 2)))
        let corruptID = UUID()
        let corruptURL = paths.threadsDirectory.appendingPathComponent("\(corruptID.uuidString).json")
        try Data("{ truncated mid-write".utf8).write(to: corruptURL)

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.threads.map(\.title), ["Survivor B", "Survivor A"])
        XCTAssertEqual(model.root.selectedThreadID, model.root.threads.first?.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path))
        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "A saved chat could not be loaded")
        XCTAssertTrue(issue.message.contains("other 2 chats are still available"))
        XCTAssertTrue(issue.message.contains("left unchanged"))
        XCTAssertEqual(issue.actionLabel, "Review diagnostics")
        XCTAssertEqual(issue.recovery?.route, .settings)
        XCTAssertEqual(issue.recovery?.reason, .savedChatsUnreadable)
        let diagnostics = Dictionary(uniqueKeysWithValues: issue.diagnostics.map { ($0.label, $0.value) })
        XCTAssertEqual(diagnostics["Loaded chats"], "2")
        XCTAssertEqual(diagnostics["Affected files"], "1")
        XCTAssertEqual(diagnostics["Chat IDs"], corruptID.uuidString.lowercased())
        XCTAssertEqual(model.surface().settings.runtimeIssue, issue)
    }

    func testBootstrapRecoversEachDamagedWorkspaceRegistryWithoutHidingHealthyChats() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        try threadStore.save(ChatThread(title: "Still here"))
        let corruptThreadID = UUID()
        try Data("{ truncated".utf8).write(
            to: paths.threadsDirectory.appendingPathComponent("\(corruptThreadID.uuidString).json")
        )
        let rejectedBytes = Data([0xFF, 0x00, 0xFE, 0x7F])
        let rejectedFiles = [
            paths.configFile,
            paths.projectsFile,
            paths.automationsFile,
            paths.sidebarSavedSearchesFile,
        ]
        for fileURL in rejectedFiles {
            try rejectedBytes.write(to: fileURL)
        }

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.threads.map(\.title), ["Still here"])
        XCTAssertEqual(model.root.config, AppConfig())
        XCTAssertTrue(model.root.projects.isEmpty)
        XCTAssertTrue(model.automations.items.isEmpty)
        XCTAssertTrue(model.sidebarSavedSearches.isEmpty)

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "Some saved workspace data could not be loaded")
        XCTAssertEqual(issue.actionLabel, "Review diagnostics")
        XCTAssertEqual(issue.recovery?.route, .settings)
        XCTAssertEqual(issue.recovery?.reason, .savedWorkspaceDataUnreadable)
        let diagnostics = Dictionary(uniqueKeysWithValues: issue.diagnostics.map { ($0.label, $0.value) })
        XCTAssertEqual(diagnostics["Affected data"], "Settings, Projects, Automations, Saved searches")
        XCTAssertEqual(diagnostics["Loaded chats"], "1")
        XCTAssertEqual(diagnostics["Affected chat files"], "1")
        XCTAssertEqual(diagnostics["Chat IDs"], corruptThreadID.uuidString.lowercased())
        let visibleRecoveryText = ([issue.title, issue.message] + issue.diagnostics.flatMap {
            [$0.label, $0.value]
        }).joined(separator: "\n")
        XCTAssertFalse(visibleRecoveryText.contains(root.path))

        _ = model.addProject(path: root, name: "Recovery session project")
        _ = model.saveSidebarSavedSearch(title: "Recovery search", query: "error")
        model.applyAutomationState(AutomationsState(items: [QuillAutomation(
            title: "Recovery automation",
            detail: "Should remain in memory only.",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "Event"
        )]))
        for fileURL in rejectedFiles {
            XCTAssertEqual(try Data(contentsOf: fileURL), rejectedBytes)
        }
    }

    func testBootstrapKeepsHealthyRegistriesWhenOneRegistryIsDamaged() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let config = AppConfig(defaultModel: "trustedrouter/glm-5.2", mode: .review)
        let project = ProjectRef(name: "Healthy project", path: root.path)
        let savedSearch = SidebarSavedSearch(title: "Failures", query: "failed")
        try ConfigStore(fileURL: paths.configFile).save(config)
        try JSONProjectStore(fileURL: paths.projectsFile).save([project])
        try JSONSidebarSavedSearchStore(fileURL: paths.sidebarSavedSearchesFile).save([savedSearch])
        let rejectedBytes = Data("{ truncated".utf8)
        try rejectedBytes.write(to: paths.automationsFile)

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.config, config)
        XCTAssertEqual(model.root.projects.map(\.id), [project.id])
        XCTAssertEqual(model.root.projects.map(\.name), [project.name])
        XCTAssertEqual(model.root.projects.map(\.path), [project.path])
        XCTAssertEqual(model.sidebarSavedSearches, [savedSearch])
        XCTAssertTrue(model.automations.items.isEmpty)
        XCTAssertEqual(try Data(contentsOf: paths.automationsFile), rejectedBytes)
        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.diagnostics.first?.value, "Automations")
    }

    func testBootstrapKeepsHealthyStateWhenAnAuxiliaryStorageDirectoryIsBlocked() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let config = AppConfig(defaultModel: "trustedrouter/glm-5.2", mode: .review)
        let project = ProjectRef(name: "Healthy project", path: root.path)
        let chat = ChatThread(title: "Healthy chat", projectID: project.id)
        try ConfigStore(fileURL: paths.configFile).save(config)
        try JSONProjectStore(fileURL: paths.projectsFile).save([project])
        try JSONThreadStore(directory: paths.threadsDirectory).save(chat)
        try FileManager.default.removeItem(at: paths.attachmentsDirectory)
        try Data("blocked".utf8).write(to: paths.attachmentsDirectory)

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.config, config)
        XCTAssertEqual(model.root.projects.map(\.id), [project.id])
        XCTAssertEqual(model.root.threads.map(\.id), [chat.id])
        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.title, "Workspace storage could not be opened")
        XCTAssertEqual(issue.recovery?.reason, .savedWorkspaceDataUnreadable)
        XCTAssertEqual(issue.diagnostics.first?.value, "Workspace storage")
        XCTAssertEqual(
            try String(contentsOf: paths.attachmentsDirectory, encoding: .utf8),
            "blocked"
        )
    }

    func testBootstrapPersistsAndClearsTrustedRouterAPIKey() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        let bootstrap = QuillCodeWorkspaceBootstrap(
            paths: paths,
            runtimeFactory: QuillCodeRuntimeFactory(
                paths: paths,
                environment: ["QUILLCODE_API_KEY_FILE": paths.home.appendingPathComponent("missing.key").path]
            )
        )

        XCTAssertFalse(bootstrap.hasTrustedRouterAPIKey())
        try bootstrap.saveTrustedRouterAPIKey("  sk-tr-v1-test  ")
        XCTAssertTrue(bootstrap.hasTrustedRouterAPIKey())

        let model = try bootstrap.makeModel()
        XCTAssertTrue(model.surface().settings.hasStoredAPIKey)

        try bootstrap.clearTrustedRouterAPIKey()
        XCTAssertFalse(bootstrap.hasTrustedRouterAPIKey())
    }
}
