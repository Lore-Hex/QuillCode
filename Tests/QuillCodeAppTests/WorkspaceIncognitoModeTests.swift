import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeReview
import QuillCodeTools
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

    func testDiscardFiresTheTaskCancellationHookAndClearsTheLiveComposer() throws {
        let model = model(threads: [], selectedThreadID: nil)
        var cancelledThreadIDs: [UUID] = []
        model.onEphemeralThreadDiscarded = { cancelledThreadIDs.append($0) }
        let incognitoID = model.newIncognitoChat()
        model.setDraft("half-typed private question")

        _ = model.newChat()

        XCTAssertEqual(cancelledThreadIDs, [incognitoID], "the desktop layer must be told to cancel the owning send task")
        XCTAssertEqual(model.composer.draft, "", "unsent private text must not survive into the next selection")
        XCTAssertTrue(model.composer.attachments.isEmpty)
    }

    func testDiscardPreservesContentFreeSpendReceipts() throws {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()
        model.mutateThread(incognitoID) { thread in
            thread.messages.append(.init(role: .user, content: "private question"))
            thread.events.append(ModelTokenUsageEvent.event(
                usage: ModelTokenUsage(promptTokens: 1_000, completionTokens: 500),
                modelID: TrustedRouterDefaults.e2eModel
            ))
        }

        _ = model.newChat()

        let receipt = try XCTUnwrap(model.discardedEphemeralSpendThreads.first)
        XCTAssertTrue(receipt.messages.isEmpty, "receipts carry usage only — never conversation content")
        XCTAssertEqual(receipt.events.count, 1)
        XCTAssertEqual(
            ModelTokenUsageEvent.usage(from: try XCTUnwrap(receipt.events.first))?.contextTokens,
            1_500,
            "the period ledger must keep counting the destroyed session's spend"
        )
    }

    func testDiscardWithoutUsageLeavesNoReceipt() {
        let model = model(threads: [], selectedThreadID: nil)
        _ = model.newIncognitoChat()

        _ = model.newChat()

        XCTAssertTrue(model.discardedEphemeralSpendThreads.isEmpty)
    }

    func testArchivingAnIncognitoThreadIsRefused() throws {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()

        XCTAssertFalse(model.archiveThread(incognitoID))

        XCTAssertNotNil(model.lastError)
        XCTAssertTrue(
            model.root.threads.contains { $0.id == incognitoID },
            "refusal must leave the live session intact (not half-archived)"
        )
    }

    func testFlailNotificationForIncognitoCarriesNoFailureOutput() throws {
        var thread = WorkspaceThreadCreationEngine.incognitoThread(projectID: nil, mode: .auto)
        let secret = "/Users/private/secret-project/main.py exploded"
        thread.messages.append(.init(role: .user, content: "question"))

        let notification = try XCTUnwrap(
            WorkspaceRunNotificationBuilder.notification(
                thread: thread,
                didFail: false,
                budgetStop: .flailed(reason: secret)
            )
        )

        XCTAssertFalse(notification.body.contains(secret), notification.body)
        XCTAssertFalse(notification.title.contains(secret))
    }

    func testIncognitoRunnerRetargetsWebSearchToTheE2ERoute() throws {
        var baseRunner = AgentRunner()
        baseRunner.webSearch = TrustedRouterWebSearchClient(model: TrustedRouterDefaults.defaultModel)

        let runner = WorkspaceAgentSendSessionFactory(
            baseRunner: baseRunner,
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: URL(fileURLWithPath: "/tmp")
        ).configuredRunner(
            modelID: TrustedRouterDefaults.e2eModel,
            threadID: UUID(),
            threadIsIncognito: true
        )

        // host.web.search makes its own chat-completions request with the private query — it must
        // ride the E2E route, never the default model.
        XCTAssertEqual(
            (runner.webSearch as? TrustedRouterWebSearchClient)?.model,
            TrustedRouterDefaults.e2eModel
        )
    }

    func testAsyncForkAndCompactEntriesAreRefusedForIncognito() {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()
        model.mutateThread(incognitoID) { thread in
            thread.messages.append(.init(role: .user, content: "private question"))
        }

        // The model-backed summary continuations bypass the synchronous fork/compact helpers; their
        // entry points must refuse too (they'd ship the transcript to an auxiliary model AND write a
        // durable continuation).
        XCTAssertFalse(model.startForkThread(strategy: .summarizedContext))
        XCTAssertFalse(model.startCompactContext(workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.root.threads.count, 1)
    }

    func testRenamingAnIncognitoThreadIsRefused() throws {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()

        XCTAssertFalse(model.renameThread(incognitoID, to: "secret project title"))

        XCTAssertEqual(try XCTUnwrap(model.selectedThread).title, "Incognito")
        XCTAssertNotNil(model.lastError)
    }

    func testNotificationTitleIsFixedEvenIfAnIncognitoTitleWasMutated() throws {
        // Defense in depth: even if some path mutates the title, notifications never carry it.
        var thread = WorkspaceThreadCreationEngine.incognitoThread(projectID: nil, mode: .auto)
        thread.title = "secret project title"
        thread.messages.append(.init(role: .user, content: "question"))
        thread.messages.append(.init(role: .assistant, content: "answer"))

        let notification = try XCTUnwrap(
            WorkspaceRunNotificationBuilder.notification(thread: thread, didFail: false)
        )

        XCTAssertFalse(notification.title.contains("secret project title"))
        XCTAssertFalse(notification.body.contains("secret project title"))
    }

    func testBackNavigationStillReachesThePreIncognitoThread() throws {
        let durable = ChatThread(
            title: "Durable work",
            messages: [.init(role: .user, content: "hello")]
        )
        let model = model(threads: [durable], selectedThreadID: durable.id)

        _ = model.newIncognitoChat()
        let newChatID = model.newChat()

        // The incognito detour is collapsed, not history-resetting: Back from the new chat must
        // still reach the durable thread the user was on before going incognito.
        XCTAssertEqual(model.root.selectedThreadID, newChatID)
        XCTAssertTrue(model.navigateBackInWorkspace(), "history must survive the incognito collapse")
        XCTAssertEqual(model.root.selectedThreadID, durable.id)
    }

    func testDirectThreadInsertionDiscardsTheSelectedIncognitoThread() throws {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()

        // Worktree create/open (and other creation flows) insert + select directly, bypassing
        // newChat/selectThread — the common insertion boundary must discard the outgoing session.
        let created = ChatThread(title: "Worktree task")
        _ = model.insertCreatedThread(created, selectedProjectID: nil, saveThread: false)

        XCTAssertEqual(model.root.selectedThreadID, created.id)
        XCTAssertFalse(model.root.threads.contains { $0.id == incognitoID })
    }

    func testManuallySelectedE2ERouteAlsoHardensAuxiliaryTraffic() throws {
        // trustedrouter/e2e is user-selectable from the Private category on a REGULAR thread; the
        // "E2E Encrypted" chip must mean no non-E2E egress there either, even without incognito.
        var baseRunner = AgentRunner()
        baseRunner.webSearch = TrustedRouterWebSearchClient(model: TrustedRouterDefaults.defaultModel)

        let runner = WorkspaceAgentSendSessionFactory(
            baseRunner: baseRunner,
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: URL(fileURLWithPath: "/tmp")
        ).configuredRunner(
            modelID: TrustedRouterDefaults.e2eModel,
            threadID: UUID(),
            threadIsIncognito: false
        )

        XCTAssertEqual(
            (runner.webSearch as? TrustedRouterWebSearchClient)?.model,
            TrustedRouterDefaults.e2eModel
        )
    }

    func testPreIncognitoDraftSurvivesTheDetour() throws {
        let durable = ChatThread(title: "Durable work", messages: [.init(role: .user, content: "hi")])
        let model = model(threads: [durable], selectedThreadID: durable.id)
        model.setDraft("half-written important message")

        _ = model.newIncognitoChat()
        model.setDraft("private text that must vanish")
        _ = model.newChat()
        model.selectThread(durable.id)

        // The incognito detour must neither leak its own draft nor erase the durable thread's
        // stashed one (the discard previously left a blank live composer that the next transition
        // persisted over the stash).
        XCTAssertEqual(model.composer.draft, "half-written important message")
    }

    func testIncognitoSlashHelperMatchesAllAliasesAndOnlyBareCommands() {
        for alias in ["/incognito", "/INCOGNITO", "  /incognito-chat ", "/private-chat"] {
            XCTAssertTrue(WorkspaceIncognitoSlash.isIncognitoCommand(alias), alias)
        }
        // The command word is matched on the FIRST token (matching the native parser, which ignores
        // /incognito's argument), but a DIFFERENT word — or no leading slash — is not the command.
        XCTAssertTrue(WorkspaceIncognitoSlash.isIncognitoCommand("/incognito ignored args"))
        XCTAssertFalse(WorkspaceIncognitoSlash.isIncognitoCommand("/incognitomode"))
        XCTAssertFalse(WorkspaceIncognitoSlash.isIncognitoCommand("incognito"))
        XCTAssertFalse(WorkspaceIncognitoSlash.isIncognitoCommand("/side"))
    }

    func testStartingIncognitoOverAnActiveSideConversationCancelsTheSideTask() throws {
        let parent = ChatThread(title: "Parent", messages: [.init(role: .user, content: "work")])
        let model = model(threads: [parent], selectedThreadID: parent.id)
        var cancelledThreadIDs: [UUID] = []
        model.onEphemeralThreadDiscarded = { cancelledThreadIDs.append($0) }
        let sideID = try XCTUnwrap(model.startSideConversation(prompt: "quick q"))

        _ = model.newIncognitoChat()

        XCTAssertTrue(cancelledThreadIDs.contains(sideID), "the replaced side conversation's send task must be cancelled")
        XCTAssertFalse(model.root.threads.contains { $0.id == sideID })
        XCTAssertTrue(try XCTUnwrap(model.selectedThread).runtimeContext.isIncognito)
    }

    func testIncognitoDetachedReviewIsCoercedToCurrentDelivery() {
        let model = model(threads: [], selectedThreadID: nil)
        _ = model.newIncognitoChat()
        let detached = WorkspaceCodeReviewRequest(scope: .uncommitted, delivery: .detached)

        let normalized = model.withNormalizedDeliveryForSelection(detached)

        XCTAssertEqual(normalized.delivery, .current, "detached would discard the private session + persist a durable review")
    }

    func testContextBannerDisablesForkAndCompactForIncognito() throws {
        var thread = WorkspaceThreadCreationEngine.incognitoThread(projectID: nil, mode: .auto)
        thread.messages = [.init(role: .user, content: String(repeating: "x", count: 130_000))]

        let banner = try XCTUnwrap(WorkspaceContextBannerBuilder(thread: thread).banner())

        XCTAssertEqual(banner.compactCommand.isEnabled, false)
        XCTAssertTrue(banner.forkCommands.allSatisfy { $0.isEnabled == false })
        XCTAssertEqual(banner.newThreadCommand.id, "new-chat", "the fresh-chat escape stays available")
        XCTAssertTrue(banner.subtitle.contains("private session"))
    }

    func testClearAndDeletePreserveIncognitoSpendReceipts() throws {
        for destroy in ["clear", "delete"] {
            let model = model(threads: [], selectedThreadID: nil)
            let incognitoID = model.newIncognitoChat()
            model.mutateThread(incognitoID) { thread in
                thread.messages.append(.init(role: .user, content: "private"))
                thread.events.append(ModelTokenUsageEvent.event(
                    usage: ModelTokenUsage(promptTokens: 800, completionTokens: 200),
                    modelID: TrustedRouterDefaults.e2eModel
                ))
            }

            if destroy == "clear" {
                _ = model.clearThread(incognitoID)
            } else {
                _ = model.deleteThread(incognitoID)
            }

            let receipt = try XCTUnwrap(model.discardedEphemeralSpendThreads.first, "\(destroy) must retain spend")
            XCTAssertTrue(receipt.messages.isEmpty)
            XCTAssertEqual(
                ModelTokenUsageEvent.usage(from: try XCTUnwrap(receipt.events.first))?.contextTokens,
                1_000
            )
        }
    }

    func testWorkspaceSurfaceDecodesLegacyPayloadWithoutIncognitoKey() throws {
        let model = model(threads: [ChatThread(title: "T")], selectedThreadID: nil)
        let encoded = try JSONEncoder().encode(model.surface())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isIncognito")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspaceSurface.self, from: legacy)

        XCTAssertFalse(decoded.isIncognito, "absent key must decode as not-incognito (@QuillCodeDefaultFalse)")
    }

    func testMemoryContextNoticeDoesNotInjectMemoriesIntoIncognito() throws {
        let note = MemoryNote(
            id: "m", scope: .global, title: "Note", content: "durable secret", relativePath: "m.md", byteCount: 13
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(globalMemories: [note]))
        let incognitoID = model.newIncognitoChat()

        // Simulates a /remember mutation that would refresh the thread's memory context — the notice
        // application must be suppressed for incognito (the prompt builder would emit these as a
        // system prompt, breaking the no-workspace-context contract).
        model.applyMemoryMutation(WorkspaceMemoryMutation(
            transcript: WorkspaceLocalCommandTranscript(userText: "/remember durable secret", assistantText: "Saved", title: "Memory"),
            updatedGlobalMemories: [note],
            updatedProjectMemories: nil,
            noticeSummary: "Saved a memory",
            noticeRelativePath: "m.md",
            reviewEvent: nil
        ))

        XCTAssertTrue(
            try XCTUnwrap(model.root.threads.first { $0.id == incognitoID }).memories.isEmpty,
            "incognito must never carry injected workspace memories"
        )
    }

    func testDeletingASelectedIncognitoThreadClearsTheErrorSurface() {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()
        model.setLastError("TrustedRouter streaming request failed with HTTP 402")

        _ = model.deleteThread(incognitoID)

        XCTAssertNil(model.lastError, "a deleted incognito run's failure must not linger into the next chat")
    }

    func testRegularThreadOnE2EModelCompactsDeterministicallyWithoutEgress() async throws {
        // A REGULAR (non-incognito) thread can select the E2E route from the Private category or via
        // `/model e2e`. Its /compact must NOT ship the transcript to the cheap non-E2E auxiliary
        // summary model — it must summarize DETERMINISTICALLY, honoring the "E2E route ⇒ no non-E2E
        // egress" invariant that the standalone summary path bypasses.
        let source = ChatThread(
            title: "E2E work",
            model: TrustedRouterDefaults.e2eModel,
            messages: [
                .init(role: .user, content: "old private question"),
                .init(role: .assistant, content: "old private answer"),
                .init(role: .user, content: "latest request"),
                .init(role: .assistant, content: "latest answer")
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [source], selectedThreadID: source.id),
            contextSummaryGenerator: ModelBackedSummaryGeneratorStub(summary: "LEAKED-MODEL-SUMMARY")
        )

        let compactCandidate = await model.compactContextWithConfiguredSummary(sourceID: source.id)
        let compactID = try XCTUnwrap(compactCandidate)
        let compacted = try XCTUnwrap(model.root.threads.first { $0.id == compactID })

        XCTAssertFalse(
            compacted.messages.contains { $0.content.contains("LEAKED-MODEL-SUMMARY") },
            "an E2E-routed thread must never reach the non-E2E model-backed summarizer"
        )
        XCTAssertTrue(
            compacted.events.last?.payloadJSON?.contains(#""source" : "e2e_deterministic""#) == true,
            "a local-by-design E2E summary is its own source — NOT deterministic_fallback, which means the model summary failed"
        )
        XCTAssertEqual(
            compacted.events.last?.summary,
            "Used a local context summary to keep this end-to-end-encrypted chat private",
            "the notice must explain the privacy reason, not claim the model summary was unavailable"
        )
    }

    func testReturningFromSideConversationRetainsContentFreeSpendReceipt() throws {
        // A side conversation is ephemeral and runs on the parent's priced (non-E2E) model. Destroying
        // it on /return must keep a content-free spend receipt — exactly like incognito discard/clear/
        // delete — or its usage vanishes from the period ledger and cycling side chats launders spend.
        let parent = ChatThread(title: "Parent", messages: [.init(role: .user, content: "work")])
        let model = model(threads: [parent], selectedThreadID: parent.id)
        let sideID = try XCTUnwrap(model.startSideConversation(prompt: "quick q"))
        model.mutateThread(sideID) { thread in
            thread.messages.append(.init(role: .user, content: "expensive side question"))
            thread.events.append(ModelTokenUsageEvent.event(
                usage: ModelTokenUsage(promptTokens: 2_000, completionTokens: 1_000),
                modelID: parent.model
            ))
        }

        XCTAssertTrue(model.returnFromSideConversation())

        let receipt = try XCTUnwrap(
            model.discardedEphemeralSpendThreads.first,
            "a destroyed side conversation's spend must still count against period limits"
        )
        XCTAssertTrue(receipt.messages.isEmpty, "receipts carry usage only — never conversation content")
        XCTAssertEqual(
            ModelTokenUsageEvent.usage(from: try XCTUnwrap(receipt.events.first))?.contextTokens,
            3_000
        )
    }

    func testClearingASelectedIncognitoThreadClearsTheErrorSurface() {
        let model = model(threads: [], selectedThreadID: nil)
        let incognitoID = model.newIncognitoChat()
        model.setLastError("TrustedRouter streaming request failed with HTTP 402")

        _ = model.clearThread(incognitoID)

        XCTAssertNil(model.lastError, "a cleared incognito run's failure must not linger in the still-private session")
    }

    private func model(threads: [ChatThread], selectedThreadID: UUID?) -> QuillCodeWorkspaceModel {
        QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: threads,
            selectedThreadID: selectedThreadID
        ))
    }
}

/// Model-backed summary spy: `isModelBacked` is true, so it stands in for the production LLM
/// summarizer. If the E2E-routing guard ever fails, its fixed sentinel summary lands in the
/// compacted thread — the test asserts it never does.
private struct ModelBackedSummaryGeneratorStub: WorkspaceContextSummaryGenerating {
    var isModelBacked: Bool { true }
    var summary: String

    func summary(for request: WorkspaceContextSummaryRequest) async throws -> String {
        summary
    }
}
