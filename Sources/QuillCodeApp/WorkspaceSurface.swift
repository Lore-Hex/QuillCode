import Foundation
import QuillCodeCore
import QuillCodeReview
import QuillCodeTools
import QuillComputerUseKit

public struct WorkspaceSurface: Codable, Sendable, Hashable {
    public var chrome: WorkspaceChromeSurface
    public var topBar: TopBarSurface
    public var projects: ProjectListSurface
    public var sidebar: SidebarSurface
    public var transcript: TranscriptSurface
    public var contextBanner: ContextBannerSurface?
    public var sideConversation: SideConversationSurface?
    /// True while the selected thread is a confidential chat: session-only, never persisted, pinned to
    /// the E2E-encrypted route. Renderers show a persistent banner so the private state is unmistakable.
    /// Default-false-on-absent so surface payloads bridged before this field existed still decode.
    @QuillCodeDefaultFalse public var isConfidential: Bool
    public var codeReviewRequest: WorkspaceCodeReviewRequest?
    public var autoReviewDenials: AutoReviewDenialsSurface?
    public var review: WorkspaceReviewSurface
    public var terminal: TerminalSurface
    public var browser: BrowserSurface
    public var extensions: WorkspaceExtensionsSurface
    public var memories: WorkspaceMemoriesSurface
    public var activity: WorkspaceActivitySurface
    public var automations: WorkspaceAutomationsSurface
    public var composer: ComposerSurface
    /// Cached index of the selected local project's files, used by the native
    /// composer to rank `@` mention suggestions live as the user types.
    public var fileMentionIndex: WorkspaceFileIndex
    /// Workspace-relative paths with uncommitted changes (from the latest `git status`),
    /// used to boost and badge changed files in the live composer `@` suggestions.
    public var changedFilePaths: Set<String>
    public var commands: [WorkspaceCommandSurface]
    public var settings: WorkspaceSettingsSurface
    public var worktreeEnvironments: WorkspaceWorktreeEnvironmentSurface
    public var runtimeIssue: RuntimeIssueSurface?
    public var lastError: String?
    /// The morning-triage return digest card (issue #877), present when the user has opened a thread's
    /// digest from the Attention section, nil otherwise.
    public var attentionDigest: AttentionDigestSurface?

    public init(
        chrome: WorkspaceChromeSurface = WorkspaceChromeSurface(),
        topBar: TopBarSurface,
        projects: ProjectListSurface,
        sidebar: SidebarSurface,
        transcript: TranscriptSurface,
        contextBanner: ContextBannerSurface? = nil,
        sideConversation: SideConversationSurface? = nil,
        isConfidential: Bool = false,
        codeReviewRequest: WorkspaceCodeReviewRequest? = nil,
        autoReviewDenials: AutoReviewDenialsSurface? = nil,
        review: WorkspaceReviewSurface,
        terminal: TerminalSurface,
        browser: BrowserSurface,
        extensions: WorkspaceExtensionsSurface = WorkspaceExtensionsSurface(),
        memories: WorkspaceMemoriesSurface = WorkspaceMemoriesSurface(),
        activity: WorkspaceActivitySurface = WorkspaceActivitySurface(),
        automations: WorkspaceAutomationsSurface = WorkspaceAutomationsSurface(),
        composer: ComposerSurface,
        fileMentionIndex: WorkspaceFileIndex = WorkspaceFileIndex(),
        changedFilePaths: Set<String> = [],
        commands: [WorkspaceCommandSurface],
        settings: WorkspaceSettingsSurface,
        worktreeEnvironments: WorkspaceWorktreeEnvironmentSurface = WorkspaceWorktreeEnvironmentSurface(),
        runtimeIssue: RuntimeIssueSurface? = nil,
        lastError: String? = nil,
        attentionDigest: AttentionDigestSurface? = nil
    ) {
        self.chrome = chrome
        self.topBar = topBar
        self.projects = projects
        self.sidebar = sidebar
        self.transcript = transcript
        self.contextBanner = contextBanner
        self.sideConversation = sideConversation
        self.isConfidential = isConfidential
        self.codeReviewRequest = codeReviewRequest
        self.autoReviewDenials = autoReviewDenials
        self.review = review
        self.terminal = terminal
        self.browser = browser
        self.extensions = extensions
        self.memories = memories
        self.activity = activity
        self.automations = automations
        self.composer = composer
        self.fileMentionIndex = fileMentionIndex
        self.changedFilePaths = changedFilePaths
        self.commands = commands
        self.settings = settings
        self.worktreeEnvironments = worktreeEnvironments
        self.runtimeIssue = runtimeIssue
        self.lastError = lastError
        self.attentionDigest = attentionDigest
    }
}

/// Identifies the model regions that can change during a coalesced progress update.
/// Full refreshes remain authoritative; these scopes only avoid rebuilding unrelated,
/// potentially filesystem-backed presentation state between progress callbacks.
public struct WorkspaceProgressSurfaceScope: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let agent = WorkspaceProgressSurfaceScope(rawValue: 1 << 0)
    public static let terminal = WorkspaceProgressSurfaceScope(rawValue: 1 << 1)
}

/// Identifies pane-only presentation changes that can reuse the current workspace projection.
/// Opening or closing one of these panes must not rebuild the transcript, sidebar, or model catalog.
public struct WorkspacePanePresentationScope: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let extensions = WorkspacePanePresentationScope(rawValue: 1 << 0)
    public static let memories = WorkspacePanePresentationScope(rawValue: 1 << 1)
    public static let activity = WorkspacePanePresentationScope(rawValue: 1 << 2)
    public static let automations = WorkspacePanePresentationScope(rawValue: 1 << 3)
}

private struct WorkspaceAgentProgressSurface {
    var chrome: WorkspaceChromeSurface
    var topBar: TopBarSurface
    var projects: ProjectListSurface
    var sidebar: SidebarSurface
    var transcript: TranscriptSurface
    var contextBanner: ContextBannerSurface?
    var sideConversation: SideConversationSurface?
    var isConfidential: Bool
    var codeReviewRequest: WorkspaceCodeReviewRequest?
    var autoReviewDenials: AutoReviewDenialsSurface?
    var review: WorkspaceReviewSurface
    var browser: BrowserSurface
    var extensions: WorkspaceExtensionsSurface
    var memories: WorkspaceMemoriesSurface
    var activity: WorkspaceActivitySurface
    var composer: ComposerSurface
    var fileMentionIndex: WorkspaceFileIndex
    var changedFilePaths: Set<String>
    var commands: [WorkspaceCommandSurface]
    var runtimeIssue: RuntimeIssueSurface?
    var lastError: String?
    var attentionDigest: AttentionDigestSurface?

    func apply(to surface: inout WorkspaceSurface) {
        surface.chrome = chrome
        surface.topBar = topBar
        surface.projects = projects
        surface.sidebar = sidebar
        surface.transcript = transcript
        surface.contextBanner = contextBanner
        surface.sideConversation = sideConversation
        surface.isConfidential = isConfidential
        surface.codeReviewRequest = codeReviewRequest
        surface.autoReviewDenials = autoReviewDenials
        surface.review = review
        surface.browser = browser
        surface.extensions = extensions
        surface.memories = memories
        surface.activity = activity
        surface.composer = composer
        surface.fileMentionIndex = fileMentionIndex
        surface.changedFilePaths = changedFilePaths
        surface.commands = commands
        surface.runtimeIssue = runtimeIssue
        surface.lastError = lastError
        surface.attentionDigest = attentionDigest
    }
}

@MainActor
public extension QuillCodeWorkspaceModel {
    func surface() -> WorkspaceSurface {
        let progress = agentProgressSurface()
        let surface = WorkspaceSurface(
            chrome: progress.chrome,
            topBar: progress.topBar,
            projects: progress.projects,
            sidebar: progress.sidebar,
            transcript: progress.transcript,
            contextBanner: progress.contextBanner,
            sideConversation: progress.sideConversation,
            isConfidential: progress.isConfidential,
            codeReviewRequest: progress.codeReviewRequest,
            autoReviewDenials: progress.autoReviewDenials,
            review: progress.review,
            terminal: terminalSurface(),
            browser: progress.browser,
            extensions: progress.extensions,
            memories: progress.memories,
            activity: progress.activity,
            automations: WorkspaceAutomationsSurfaceBuilder(
                isVisible: automations.isVisible,
                automations: automations.items,
                hasSelectedThread: selectedThread != nil,
                hasSelectedProject: selectedProject != nil
            ).surface(),
            composer: progress.composer,
            fileMentionIndex: progress.fileMentionIndex,
            changedFilePaths: progress.changedFilePaths,
            commands: progress.commands,
            settings: WorkspaceSettingsSurface(
                config: root.config,
                hasStoredAPIKey: root.trustedRouterAPIKeyConfigured,
                runtimeIssue: progress.runtimeIssue,
                computerUseRuntime: ComputerUseSettingsRuntime(topBarState: root.topBar),
                modelCatalogStatus: root.modelCatalogStatus,
                modelProviderHealthSummary: ModelProviderHealthSummary.summarize(root.modelCatalog),
                trustedRouterCredits: root.trustedRouterCredits,
                managedWorktreeDefaultRoot: managedWorktreeDefaultRoot
            ),
            worktreeEnvironments: selectedProject.flatMap {
                worktreeEnvironmentSurfacesByProjectID[$0.id]
            } ?? WorkspaceWorktreeEnvironmentSurface(),
            runtimeIssue: progress.runtimeIssue,
            lastError: progress.lastError,
            attentionDigest: progress.attentionDigest
        )
        agentTranscriptRefreshTracker.didPublishAuthoritativeSurface(
            selectedThreadID: root.selectedThreadID
        )
        return surface
    }

    /// Reprojects only state that the named progress producers are allowed to mutate.
    /// The returned value preserves all other value-semantic storage from `surface`.
    func progressSurface(
        reusing surface: WorkspaceSurface,
        scope: WorkspaceProgressSurfaceScope
    ) -> WorkspaceSurface {
        guard !scope.isEmpty else { return surface }
        var next = surface
        if scope.contains(.agent) {
            let transcriptRefresh = agentTranscriptRefreshTracker.consume(
                selectedThreadID: root.selectedThreadID
            )
            agentProgressSurface(
                reusing: surface.transcript,
                transcriptRefresh: transcriptRefresh
            ).apply(to: &next)
        }
        if scope.contains(.terminal) {
            next.terminal = terminalSurface()
            if !scope.contains(.agent) {
                next.commands = commandSurfaceBuilder().commands
                applyTerminalStatus(to: &next)
            }
        }
        return next
    }

    /// Reprojects only pane presentation state after a visibility toggle. Pane contents are already
    /// refreshed by their owning model mutations; Extensions is rebuilt because toggling it also
    /// clears its focused kind and therefore changes its filtered item set.
    func panePresentationSurface(
        reusing surface: WorkspaceSurface,
        scope: WorkspacePanePresentationScope
    ) -> WorkspaceSurface {
        guard !scope.isEmpty else { return surface }
        var next = surface
        if scope.contains(.extensions) {
            next.extensions = extensionsSurface()
        }
        if scope.contains(.memories) {
            next.memories = surface.memories.settingVisibility(memories.isVisible)
        }
        if scope.contains(.activity) {
            next.activity = surface.activity.settingVisibility(activity.isVisible)
        }
        if scope.contains(.automations) {
            next.automations = surface.automations.settingVisibility(automations.isVisible)
        }
        return next
    }

    private func extensionsSurface() -> WorkspaceExtensionsSurface {
        WorkspaceExtensionsSurface(
            isVisible: extensions.isVisible,
            focusedKind: extensions.focusedKind,
            manifests: selectedProject?.extensionManifests ?? [],
            hooks: effectiveHookDefinitions(for: selectedProject),
            mcpServerStatuses: extensions.mcpServerStatuses,
            mcpServerProbeSummaries: extensions.mcpServerProbeSummaries,
            workflowRecording: (computerUseBackend as? any WorkflowRecordingStatusProviding)?
                .workflowRecordingStatusSnapshot
        )
    }

    private func agentProgressSurface(
        reusing previousTranscript: TranscriptSurface? = nil,
        transcriptRefresh: WorkspaceAgentTranscriptRefreshPlan = .rebuild
    ) -> WorkspaceAgentProgressSurface {
        let thread = selectedThread
        let topBarState = root.topBar
        let runtimeIssue = runtimeIssueSurface()
        let executionContextBuilder = WorkspaceExecutionContextSurfaceBuilder(
            selectedProject: selectedProject,
            projects: root.projects
        )
        let transcript: TranscriptSurface
        if var incrementalTranscript = previousTranscript.flatMap({
            transcriptRefresh.updatingTranscript($0, for: thread)
        }) {
            incrementalTranscript.thinking = WorkspaceTranscriptThinkingSurfaceBuilder(
                thread: thread,
                composer: composer,
                agentStatus: topBarState.agentStatus
            ).surface()
            transcript = incrementalTranscript
        } else {
            let transcriptProjection = thread.map {
                WorkspaceTranscriptSurfaceBuilder(
                    thread: $0,
                    allowsRevert: selectedProject?.isRemote != true
                ).projection()
            } ?? .empty
            let toolCards = thread.map {
                executionContextBuilder.enrichToolCards(transcriptProjection.toolCards, for: $0)
            } ?? []
            let timelineItems = thread.map {
                executionContextBuilder.enrichTimelineItems(transcriptProjection.timelineItems, for: $0)
            } ?? []
            transcript = TranscriptSurface(
                messages: transcriptProjection.messages,
                toolCards: toolCards,
                timelineItems: thread == nil ? nil : timelineItems,
                thinking: WorkspaceTranscriptThinkingSurfaceBuilder(
                    thread: thread,
                    composer: composer,
                    agentStatus: topBarState.agentStatus
                ).surface()
            )
        }
        let toolCards = transcript.toolCards
        let activeSources = WorkspaceContextResolver(
            projects: root.projects,
            globalMemories: root.globalMemories,
            selectedProject: selectedProject
        ).activeSources(for: thread)
        let activeProjectID = thread?.projectID ?? root.selectedProjectID
        let canEditProjectMemories = activeProjectID
            .flatMap { projectID in root.projects.first { $0.id == projectID } }
            .map { _ in true } ?? false
        let dismissedInstructionDiagnosticIDs = activity.dismissedInstructionDiagnosticIDs.union(
            activeProjectID
                .flatMap { projectID in root.projects.first { $0.id == projectID } }
                .map(\.dismissedInstructionDiagnosticIDs) ?? []
        )
        let sidebarSelectedThreadIDs = sidebarSelection.isActive
            ? Set(selectedSidebarThreadIDs())
            : []
        let navigation = WorkspaceNavigationSurfaceBuilder(
            projects: root.projects,
            selectedProjectID: root.selectedProjectID,
            refreshingProjectIDs: refreshingProjectContextIDs,
            sidebarItems: root.allSidebarItems,
            selectedThreadID: root.selectedThreadID,
            threads: root.threads,
            activeSidebarFilter: sidebarFilter,
            activeSidebarSavedSearchID: activeSidebarSavedSearchID,
            sidebarSavedSearches: sidebarSavedSearches,
            selectionIsActive: sidebarSelection.isActive,
            selectedThreadIDs: sidebarSelectedThreadIDs,
            agentRuns: agentRuns,
            attentionCursorID: attentionCursorID
        ).surface()
        let spendPeriodThreads = root.threads + discardedEphemeralSpendLedger.periodThreads()
        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: topBarState,
            thread: thread,
            projectName: root.topBar.projectName,
            instructions: activeSources.instructions,
            memories: activeSources.memories,
            modelCatalog: root.modelCatalog,
            modelCatalogStatus: root.modelCatalogStatus,
            defaultModelID: root.config.defaultModel,
            favoriteModelIDs: root.config.favoriteModels,
            recentThreads: root.threads,
            spendPeriodThreads: spendPeriodThreads,
            runtimeIssue: runtimeIssue,
            trustedRouterCredits: root.trustedRouterCredits,
            hasTrustedRouterCredential: root.trustedRouterAPIKeyConfigured,
            runSpendFuseUSD: root.config.runSpendFuseUSD,
            runSpendPeriodLimits: root.config.runSpendPeriodLimits,
            canNavigateBack: navigationHistory.canGoBack,
            canNavigateForward: navigationHistory.canGoForward
        ).surface()
        // Compute the review (git-diff) surface once and reuse it: the review pane renders it in full,
        // and the Activity pane's `.changes` section shows a glanceable per-file roll-up of the same delta.
        var review = WorkspaceReviewSurfaceBuilder(
            toolCards: toolCards,
            events: thread?.events ?? [],
            thread: thread,
            selectionOverride: reviewSelectionOverride,
            allowsTurnRevert: selectedProject?.isRemote != true,
            pullRequestReviewDraft: pullRequestReviewDraft
        ).surface()
        review.isPresented = chrome.reviewPresentation.resolves(hasContent: review.hasContent)
        return WorkspaceAgentProgressSurface(
            chrome: WorkspaceChromeSurface(state: chrome, reviewHasContent: review.hasContent),
            topBar: topBar,
            projects: navigation.projects,
            sidebar: navigation.sidebar,
            transcript: transcript,
            contextBanner: WorkspaceContextBannerBuilder(
                thread: thread,
                selectedModelID: topBarState.model,
                modelCatalog: root.modelCatalog
            ).banner(),
            sideConversation: sideConversationSurface(),
            isConfidential: thread?.runtimeContext.isConfidential == true,
            codeReviewRequest: codeReviewRequest,
            autoReviewDenials: isAutoReviewDenialsPresented
                ? AutoReviewDenialsSurfaceBuilder.surface(
                    thread: thread,
                    workspaceRoot: activeWorkspaceRoot,
                    retryingRequestID: autoReviewDenialRetryingRequestID
                )
                : nil,
            review: review,
            browser: BrowserSurface(browser: browser),
            extensions: extensionsSurface(),
            memories: WorkspaceMemoriesSurface(
                isVisible: memories.isVisible,
                notes: activeSources.memories,
                events: thread?.events ?? [],
                canEditProjectMemories: canEditProjectMemories
            ),
            activity: WorkspaceActivitySurface(
                isVisible: activity.isVisible,
                thread: thread,
                toolCards: toolCards,
                instructions: activeSources.instructions,
                memories: activeSources.memories,
                agentStatus: topBarState.agentStatus,
                changeFiles: review.files,
                modelCatalog: root.modelCatalog,
                runSpendFuseUSD: root.config.runSpendFuseUSD,
                collapsedSectionIDs: activity.collapsedSectionIDs,
                dismissedInstructionDiagnosticIDs: dismissedInstructionDiagnosticIDs
            ),
            composer: ComposerSurface(
                composer: composer,
                fileMentionIndex: fileMentionIndex,
                changedFilePaths: activeChangedFilePaths,
                sentMessageHistory: ComposerHistoryRecall.history(from: thread?.messages ?? []),
                planProgress: WorkspacePlanProgressBuilder.progress(for: thread, agentStatus: topBarState.agentStatus),
                followUpQueue: thread?.followUpQueue ?? [],
                supportsPersonality: WorkspaceConfigurationEngine.modelSupportsPersonality(
                    thread?.model ?? root.config.defaultModel,
                    catalog: root.modelCatalog
                )
            ),
            fileMentionIndex: fileMentionIndex,
            changedFilePaths: activeChangedFilePaths,
            commands: commandSurfaceBuilder().commands,
            runtimeIssue: runtimeIssue,
            lastError: lastError,
            attentionDigest: attentionDigestSurface()
        )
    }

    private func terminalSurface() -> TerminalSurface {
        TerminalSurface(terminal: terminal, cwd: terminalCurrentDirectoryURL)
    }

    private func applyTerminalStatus(to surface: inout WorkspaceSurface) {
        let runtimeIssue = runtimeIssueSurface()
        surface.topBar.agentStatus = root.topBar.agentStatus
        surface.topBar.runtimeIssueLabel = runtimeIssue?.title
        surface.topBar.runtimeIssueSeverity = runtimeIssue?.severity
        surface.topBar.branchStatusLabel = WorkspaceTopBarSurfaceBuilder.branchStatusLabel(
            for: root.topBar.branchStatus
        )
        surface.runtimeIssue = runtimeIssue
        surface.lastError = lastError
    }

    /// The morning-triage return digest for the currently opened digest thread (issue #877), or nil when
    /// none is open. The unseen-turn seam reuses the persisted return watermark so it matches what the
    /// user last saw across sessions.
    private func attentionDigestSurface() -> AttentionDigestSurface? {
        guard let digestThreadID = attentionDigestThreadID,
              let thread = root.threads.first(where: { $0.id == digestThreadID })
        else {
            return nil
        }
        let unseen = ThreadReturnWatermarkRecord.unseenCount(in: thread)
        return AttentionDigestSurface(digest: TriageDigest.build(for: thread, unseenCount: unseen))
    }

    private func runtimeIssueSurface() -> RuntimeIssueSurface? {
        if let startupLoadIssue {
            return startupLoadIssue.runtimeIssue
        }
        if let persistenceIssue = threadPersistenceIssueTracker.runtimeIssue {
            return persistenceIssue
        }
        if let persistenceIssue = registryPersistenceIssueTracker.runtimeIssue {
            return persistenceIssue
        }
        if let persistenceIssue = settingsPersistenceIssueTracker.runtimeIssue {
            return persistenceIssue
        }
        return WorkspaceRuntimeIssueBuilder(
            config: root.config,
            hasStoredAPIKey: root.trustedRouterAPIKeyConfigured,
            modelID: root.topBar.model,
            agentStatus: root.topBar.agentStatus,
            lastError: lastError
        ).surface()
    }

    private func commandSurfaceBuilder() -> WorkspaceCommandSurfaceBuilder {
        let sidebarSelectedThreadIDs = Set(selectedSidebarThreadIDs())
        let selectedSidebarThreads = root.threads.filter { sidebarSelectedThreadIDs.contains($0.id) }
        let visibleSidebarItemCount = filteredSidebarItems().count
        let workflowRecordingStatus = (computerUseBackend as? any WorkflowRecordingStatusProviding)?
            .workflowRecordingStatusSnapshot
        return WorkspaceCommandSurfaceBuilder(
            selectedThread: selectedThread,
            selectedProject: selectedProject,
            projectContextRefreshIsActive: selectedProject.map {
                refreshingProjectContextIDs.contains($0.id)
            } ?? false,
            hooks: effectiveHookDefinitions(for: selectedProject),
            selectedSidebarThreads: selectedSidebarThreads,
            sidebarSelectionIsActive: sidebarSelection.isActive,
            sidebarItemCount: visibleSidebarItemCount,
            sidebarSavedSearches: sidebarSavedSearches,
            hasActiveWorkspaceRoot: activeWorkspaceRoot != nil,
            canRetryLastUserTurn: canRetryLastUserTurn,
            composerIsSending: activeAgentRunCount > 0,
            terminalHasEntries: !terminal.entries.isEmpty,
            terminalIsRunning: terminal.isRunning,
            browserCanGoBack: browser.canGoBack,
            browserCanGoForward: browser.canGoForward,
            browserCanReload: browser.canReload,
            browserCanOpenSession: browserCanOpenSession,
            canNavigateBack: navigationHistory.canGoBack,
            canNavigateForward: navigationHistory.canGoForward,
            mcpServerStatuses: extensions.mcpServerStatuses,
            mcpServerProbeSummaries: extensions.mcpServerProbeSummaries,
            computerUseStatus: root.topBar.computerUseStatus,
            workflowRecordingAvailable: computerUseBackend is any WorkflowRecordingBackend,
            workflowRecordingIsActive: workflowRecordingStatus?.isRecording == true,
            selectedThreadIsRunning: isAgentRunActive(for: root.selectedThreadID),
            runningThreadIDs: activeAgentRunThreadIDs,
            shortcutProfile: WorkspaceShortcutRegistry.profile(
                preferences: root.config.keyboardShortcuts
            )
        )
    }

    private var browserCanOpenSession: Bool {
        browser.currentURL != nil
            || !browser.addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}
