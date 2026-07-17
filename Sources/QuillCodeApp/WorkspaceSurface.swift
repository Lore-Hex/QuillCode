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
    /// True while the selected thread is an incognito chat: session-only, never persisted, pinned to
    /// the E2E-encrypted route. Renderers show a persistent banner so the private state is unmistakable.
    public var isIncognito: Bool
    public var codeReviewRequest: WorkspaceCodeReviewRequest?
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
        isIncognito: Bool = false,
        codeReviewRequest: WorkspaceCodeReviewRequest? = nil,
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
        self.isIncognito = isIncognito
        self.codeReviewRequest = codeReviewRequest
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

@MainActor
public extension QuillCodeWorkspaceModel {
    func surface() -> WorkspaceSurface {
        let thread = selectedThread
        let topBarState = root.topBar
        let toolCards = currentToolCards
        let runtimeIssue = runtimeIssueSurface()
        let transcriptMessages = thread.map {
            WorkspaceTranscriptSurfaceBuilder(
                thread: $0,
                allowsRevert: selectedProject?.isRemote != true
            ).messageSurfaces()
        } ?? []
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
        return WorkspaceSurface(
            chrome: WorkspaceChromeSurface(state: chrome, reviewHasContent: review.hasContent),
            topBar: topBar,
            projects: navigation.projects,
            sidebar: navigation.sidebar,
            transcript: TranscriptSurface(
                messages: transcriptMessages,
                toolCards: toolCards,
                timelineItems: thread == nil ? nil : currentTimelineItems,
                thinking: WorkspaceTranscriptThinkingSurfaceBuilder(
                    thread: thread,
                    composer: composer,
                    agentStatus: topBarState.agentStatus
                ).surface()
            ),
            contextBanner: WorkspaceContextBannerBuilder(
                thread: thread,
                selectedModelID: topBarState.model,
                modelCatalog: root.modelCatalog
            ).banner(),
            sideConversation: sideConversationSurface(),
            isIncognito: thread?.runtimeContext.isIncognito == true,
            codeReviewRequest: codeReviewRequest,
            review: review,
            terminal: TerminalSurface(
                terminal: terminal,
                cwd: terminalCurrentDirectoryURL
            ),
            browser: BrowserSurface(browser: browser),
            extensions: WorkspaceExtensionsSurface(
                isVisible: extensions.isVisible,
                focusedKind: extensions.focusedKind,
                manifests: selectedProject?.extensionManifests ?? [],
                hooks: effectiveHookDefinitions(for: selectedProject),
                mcpServerStatuses: extensions.mcpServerStatuses,
                mcpServerProbeSummaries: extensions.mcpServerProbeSummaries,
                workflowRecording: (computerUseBackend as? any WorkflowRecordingStatusProviding)?
                    .workflowRecordingStatusSnapshot
            ),
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
            automations: WorkspaceAutomationsSurfaceBuilder(
                isVisible: automations.isVisible,
                automations: automations.items,
                hasSelectedThread: thread != nil,
                hasSelectedProject: selectedProject != nil
            ).surface(),
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
            settings: WorkspaceSettingsSurface(
                config: root.config,
                hasStoredAPIKey: root.trustedRouterAPIKeyConfigured,
                runtimeIssue: runtimeIssue,
                computerUseRuntime: ComputerUseSettingsRuntime(topBarState: topBarState),
                modelCatalogStatus: root.modelCatalogStatus,
                modelProviderHealthSummary: ModelProviderHealthSummary.summarize(root.modelCatalog),
                trustedRouterCredits: root.trustedRouterCredits,
                managedWorktreeDefaultRoot: managedWorktreeDefaultRoot
            ),
            worktreeEnvironments: selectedProject.flatMap { project in
                guard !project.isRemote else { return nil }
                return WorkspaceProjectConfigurationLoader
                    .load(from: URL(fileURLWithPath: project.path))
                    .worktreeEnvironmentSurface
            } ?? WorkspaceWorktreeEnvironmentSurface(),
            runtimeIssue: runtimeIssue,
            lastError: lastError,
            attentionDigest: attentionDigestSurface()
        )
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
        WorkspaceRuntimeIssueBuilder(
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
