import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceIncognitoModeTests: XCTestCase {
    func testIncognitoThreadFactoryPinsE2EModelAndCarriesNoWorkspaceContext() {
        let projectID = UUID()

        let thread = WorkspaceThreadCreationEngine.incognitoThread(projectID: projectID, mode: .plan)

        XCTAssertTrue(thread.runtimeContext.isIncognito)
        XCTAssertTrue(thread.runtimeContext.isEphemeral)
        XCTAssertEqual(thread.model, TrustedRouterDefaults.e2eModel)
        XCTAssertEqual(thread.projectID, projectID)
        XCTAssertEqual(thread.mode, .plan)
        XCTAssertEqual(thread.title, "Incognito")
        // An incognito conversation neither reads from nor contributes to durable workspace context.
        XCTAssertTrue(thread.instructions.isEmpty)
        XCTAssertTrue(thread.memories.isEmpty)
        XCTAssertTrue(thread.messages.isEmpty)
        XCTAssertEqual(thread.events.map(\.summary), ["Incognito chat: not saved, routed end-to-end encrypted"])
    }

    func testNewIncognitoChatSelectsPinnedThreadAndStaysOutOfTheSidebar() throws {
        let existing = ChatThread(title: "Regular work")
        let model = model(threads: [existing], selectedThreadID: existing.id)

        let incognitoID = model.newIncognitoChat()
        let selected = try XCTUnwrap(model.selectedThread)

        XCTAssertEqual(selected.id, incognitoID)
        XCTAssertTrue(selected.runtimeContext.isIncognito)
        XCTAssertEqual(selected.model, TrustedRouterDefaults.e2eModel)
        // Ephemeral threads never appear in the sidebar (or its unfiltered variant) — the incognito
        // chat exists only as the current selection.
        XCTAssertEqual(model.root.sidebarItems.map(\.id), [existing.id])
        XCTAssertEqual(model.root.allSidebarItems.map(\.id), [existing.id])
    }

    func testSetModelIsANoOpInsideAnIncognitoChat() throws {
        let model = model(threads: [], selectedThreadID: nil)
        let defaultModelBefore = model.root.config.defaultModel
        _ = model.newIncognitoChat()

        let returned = model.setModel(TrustedRouterDefaults.zeusModel)

        let selected = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(returned, TrustedRouterDefaults.e2eModel, "the gesture reports the pinned model")
        XCTAssertEqual(selected.model, TrustedRouterDefaults.e2eModel, "the thread's model stays pinned")
        XCTAssertEqual(
            model.root.config.defaultModel,
            defaultModelBefore,
            "a switch attempted inside incognito must not quietly reconfigure future normal chats"
        )
    }

    func testSetModelStillWorksForStandardThreadsAfterIncognitoGuard() throws {
        let regular = ChatThread(title: "Regular")
        let model = model(threads: [regular], selectedThreadID: regular.id)

        let returned = model.setModel(TrustedRouterDefaults.zeusModel)

        XCTAssertEqual(returned, TrustedRouterDefaults.zeusModel)
        XCTAssertEqual(try XCTUnwrap(model.selectedThread).model, TrustedRouterDefaults.zeusModel)
    }

    func testE2ERouteIsInTheBundledCatalogAndAliasMap() {
        let entry = TrustedRouterDefaults.bundledModelCatalog.first { $0.id == TrustedRouterDefaults.e2eModel }
        XCTAssertEqual(entry?.displayName, TrustedRouterDefaults.e2eModelDisplayName)
        XCTAssertEqual(entry?.category, TrustedRouterDefaults.privateCategory)
        XCTAssertEqual(entry?.provider, TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.modelIDAliases["e2e"], TrustedRouterDefaults.e2eModel)
        XCTAssertEqual(TrustedRouterDefaults.modelIDAliases["tr/e2e"], TrustedRouterDefaults.e2eModel)
        // The E2E route is a privacy pin, not a general recommendation: keep it out of Recommended.
        XCTAssertFalse(TrustedRouterDefaults.recommendedModelIDs.contains(TrustedRouterDefaults.e2eModel))
    }

    func testLeavingIncognitoDestroysTheThreadAndPrunesNavigationHistory() throws {
        let durable = ChatThread(title: "Durable work")
        let model = model(threads: [durable], selectedThreadID: durable.id)

        let incognitoID = model.newIncognitoChat()
        _ = model.newChat()

        // Destroyed outright: not in memory, and Workspace Back can never resurrect it.
        XCTAssertFalse(model.root.threads.contains { $0.id == incognitoID })
        XCTAssertFalse(model.navigationHistory.entries.contains { $0.threadID == incognitoID })
        var reachable: Set<UUID> = []
        while model.navigateBackInWorkspace() {
            if let id = model.root.selectedThreadID { reachable.insert(id) }
        }
        XCTAssertFalse(reachable.contains(incognitoID), "back-navigation reached the destroyed incognito thread")
    }

    func testSelectingAnotherThreadDestroysTheIncognitoThread() throws {
        let durable = ChatThread(title: "Durable work")
        let model = model(threads: [durable], selectedThreadID: durable.id)
        let incognitoID = model.newIncognitoChat()

        model.selectThread(durable.id)

        XCTAssertEqual(model.root.selectedThreadID, durable.id)
        XCTAssertFalse(model.root.threads.contains { $0.id == incognitoID })
    }

    func testDurableContinuationsAreRefusedInsideIncognito() throws {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()
        model.mutateThread(incognitoID) { thread in
            thread.messages.append(.init(role: .user, content: "private question"))
            thread.messages.append(.init(role: .assistant, content: "private answer"))
        }

        // Typed /fork, /compact, and /duplicate bypass palette isEnabled — the MODEL must refuse,
        // because each creates a durable (saveThread: true) copy of the private transcript.
        XCTAssertNil(model.forkThread(strategy: .latestTurn))
        XCTAssertNil(model.compactContext())
        XCTAssertNil(model.duplicateThread(incognitoID))
        XCTAssertEqual(model.root.threads.count, 1, "no durable continuation thread may be created")
        XCTAssertNotNil(model.lastError)
    }

    func testIncognitoContextIsNeverRefilledFromTheWorkspace() {
        var thread = WorkspaceThreadCreationEngine.incognitoThread(projectID: nil, mode: .auto)
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            instructions: [ProjectInstruction(path: "AGENTS.md", title: "Rules", content: "Use Swift.", byteCount: 10)]
        )

        // The per-send sync must not refill the deliberately-empty incognito context from the
        // project/global fallback...
        WorkspaceProjectContextRefresher.syncThreadContext(
            &thread,
            fallbackProjectID: project.id,
            projects: [project],
            globalMemories: [MemoryNote(
                id: "m", scope: .global, title: "Note", content: "durable", relativePath: "m.md", byteCount: 7
            )]
        )
        XCTAssertTrue(thread.instructions.isEmpty)
        XCTAssertTrue(thread.memories.isEmpty)

        // ...and neither may the surface-level resolver.
        let sources = WorkspaceContextResolver(
            projects: [project],
            globalMemories: [MemoryNote(
                id: "m", scope: .global, title: "Note", content: "durable", relativePath: "m.md", byteCount: 7
            )],
            selectedProject: project
        ).activeSources(for: thread)
        XCTAssertTrue(sources.instructions.isEmpty)
        XCTAssertTrue(sources.memories.isEmpty)
    }

    func testRunNotificationForIncognitoCarriesNoReplyText() throws {
        var thread = WorkspaceThreadCreationEngine.incognitoThread(projectID: nil, mode: .auto)
        let secret = "the private answer nobody else may read"
        thread.messages.append(.init(role: .user, content: "question"))
        thread.messages.append(.init(role: .assistant, content: secret))

        let notification = try XCTUnwrap(
            WorkspaceRunNotificationBuilder.notification(thread: thread, didFail: false)
        )

        // OS notification history persists outside the guarded store: ping yes, content no.
        XCTAssertFalse(notification.title.contains(secret))
        XCTAssertFalse(notification.body.contains(secret))
    }

    func testSlashIncognitoParsesToTheNewIncognitoChatCommand() {
        XCTAssertEqual(SlashCommandParser.parse("/incognito"), .workspaceCommand("new-incognito-chat"))
        XCTAssertEqual(SlashCommandParser.parse("/incognito-chat"), .workspaceCommand("new-incognito-chat"))
        XCTAssertEqual(SlashCommandParser.parse("/private-chat"), .workspaceCommand("new-incognito-chat"))
    }

    func testSideConversationReturnCommandIsHiddenInsideIncognito() throws {
        let model = model(threads: [], selectedThreadID: nil)
        _ = model.newIncognitoChat()

        let surface = model.surface()

        XCTAssertNil(
            surface.commands.first { $0.id == "side-conversation-return" },
            "incognito has no parent chat to return to; the command must not surface"
        )
        // And the planner refuses it even if invoked directly.
        let planner = WorkspaceCommandActionPlanner(
            selectedProjectID: nil,
            selectedProject: nil,
            selectedThreadID: model.root.selectedThreadID,
            selectedThread: model.selectedThread
        )
        XCTAssertNil(planner.effect(for: .sideConversationReturn))
    }

    func testSavingSettingsDoesNotOverwriteTheIncognitoModelPin() throws {
        let model = model(threads: [], selectedThreadID: nil)
        _ = model.newIncognitoChat()
        var config = model.root.config
        config.defaultModel = TrustedRouterDefaults.zeusModel

        model.applySettings(config: config, trustedRouterAPIKeyConfigured: true)

        XCTAssertEqual(
            try XCTUnwrap(model.selectedThread).model,
            TrustedRouterDefaults.e2eModel,
            "a Settings save (even unrelated) must not retarget the pinned E2E route"
        )
        XCTAssertEqual(model.root.config.defaultModel, TrustedRouterDefaults.zeusModel)
    }

    func testAgentRunSnapshotCannotResurrectADiscardedIncognitoThread() throws {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()
        let snapshot = try XCTUnwrap(model.selectedThread)

        _ = model.newChat()
        XCTAssertFalse(model.root.threads.contains { $0.id == incognitoID })

        // A racing in-flight send's progress callback delivers the run's own thread snapshot; the
        // destroyed ephemeral thread must NOT be upserted back into memory.
        model.updateThreadFromAgentRun(snapshot)

        XCTAssertFalse(model.root.threads.contains { $0.id == incognitoID })
    }

    func testUnarchivingAThreadDiscardsTheSelectedIncognitoThread() throws {
        let archived = ChatThread(title: "Archived work", isArchived: true)
        let model = model(threads: [archived], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()

        XCTAssertTrue(model.unarchiveThread(archived.id))

        XCTAssertEqual(model.root.selectedThreadID, archived.id)
        XCTAssertFalse(
            model.root.threads.contains { $0.id == incognitoID },
            "unarchive selects directly (not via selectThread); the incognito discard must still run"
        )
    }

    func testDiscardClearsTheWorkspaceErrorSurface() {
        let model = model(threads: [], selectedThreadID: nil)
        _ = model.newIncognitoChat()
        model.setLastError("TrustedRouter streaming request failed with HTTP 402")

        _ = model.newChat()

        XCTAssertNil(
            model.lastError,
            "an incognito run's failure must not linger as a runtime-issue card in the next chat"
        )
    }

    func testSettingsEngineSyncPreservesIncognitoModel() {
        var thread = WorkspaceThreadCreationEngine.incognitoThread(projectID: nil, mode: .auto)
        var config = AppConfig()
        config.defaultModel = TrustedRouterDefaults.zeusModel
        config.mode = .review

        WorkspaceConfigurationEngine.syncThread(&thread, to: config)

        XCTAssertEqual(thread.model, TrustedRouterDefaults.e2eModel, "the pin survives")
        XCTAssertEqual(thread.mode, .review, "non-model settings still apply")
    }

    func testModelLabelFallsBackToBundledDisplayNameForFeaturePinnedRoutes() {
        // The LIVE catalog may not list trustedrouter/e2e; the locked chip must show the bundled
        // display name, never a raw route id.
        let label = WorkspaceModelCatalogSurfaceBuilder(
            catalog: [],
            selectedModelID: TrustedRouterDefaults.e2eModel,
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentModelIDs: []
        ).modelLabel()

        XCTAssertTrue(label.contains(TrustedRouterDefaults.e2eModelDisplayName), label)
    }

    private func model(threads: [ChatThread], selectedThreadID: UUID?) -> QuillCodeWorkspaceModel {
        QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: threads,
            selectedThreadID: selectedThreadID
        ))
    }
}
