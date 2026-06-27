import Foundation
import QuillCodeCore
import QuillCodeTools

public struct WorkspaceSurface: Codable, Sendable, Hashable {
    public var topBar: TopBarSurface
    public var projects: ProjectListSurface
    public var sidebar: SidebarSurface
    public var transcript: TranscriptSurface
    public var contextBanner: ContextBannerSurface?
    public var review: WorkspaceReviewSurface
    public var terminal: TerminalSurface
    public var browser: BrowserSurface
    public var extensions: WorkspaceExtensionsSurface
    public var memories: WorkspaceMemoriesSurface
    public var activity: WorkspaceActivitySurface
    public var automations: WorkspaceAutomationsSurface
    public var composer: ComposerSurface
    public var commands: [WorkspaceCommandSurface]
    public var settings: WorkspaceSettingsSurface
    public var runtimeIssue: RuntimeIssueSurface?
    public var lastError: String?

    public init(
        topBar: TopBarSurface,
        projects: ProjectListSurface,
        sidebar: SidebarSurface,
        transcript: TranscriptSurface,
        contextBanner: ContextBannerSurface? = nil,
        review: WorkspaceReviewSurface,
        terminal: TerminalSurface,
        browser: BrowserSurface,
        extensions: WorkspaceExtensionsSurface = WorkspaceExtensionsSurface(),
        memories: WorkspaceMemoriesSurface = WorkspaceMemoriesSurface(),
        activity: WorkspaceActivitySurface = WorkspaceActivitySurface(),
        automations: WorkspaceAutomationsSurface = WorkspaceAutomationsSurface(),
        composer: ComposerSurface,
        commands: [WorkspaceCommandSurface],
        settings: WorkspaceSettingsSurface,
        runtimeIssue: RuntimeIssueSurface? = nil,
        lastError: String? = nil
    ) {
        self.topBar = topBar
        self.projects = projects
        self.sidebar = sidebar
        self.transcript = transcript
        self.contextBanner = contextBanner
        self.review = review
        self.terminal = terminal
        self.browser = browser
        self.extensions = extensions
        self.memories = memories
        self.activity = activity
        self.automations = automations
        self.composer = composer
        self.commands = commands
        self.settings = settings
        self.runtimeIssue = runtimeIssue
        self.lastError = lastError
    }
}

@MainActor
public extension QuillCodeWorkspaceModel {
    func surface() -> WorkspaceSurface {
        let thread = selectedThread
        let topBarState = root.topBar
        let computerUse = topBarState.computerUseStatus
        let toolCards = currentToolCards
        let runtimeIssue = runtimeIssueSurface()
        let activeSources = WorkspaceContextResolver(
            projects: root.projects,
            globalMemories: root.globalMemories,
            selectedProject: selectedProject
        ).activeSources(for: thread)
        let activeProjectID = thread?.projectID ?? root.selectedProjectID
        let canEditProjectMemories = activeProjectID
            .flatMap { projectID in root.projects.first { $0.id == projectID } }
            .map { _ in true } ?? false
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
            selectionIsActive: sidebarSelection.isActive,
            selectedThreadIDs: sidebarSelectedThreadIDs
        ).surface()
        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: topBarState,
            thread: thread,
            projectName: root.topBar.projectName,
            instructions: activeSources.instructions,
            memories: activeSources.memories,
            modelCatalog: root.modelCatalog,
            defaultModelID: root.config.defaultModel,
            favoriteModelIDs: root.config.favoriteModels,
            recentThreads: root.threads,
            runtimeIssue: runtimeIssue
        ).surface()
        return WorkspaceSurface(
            topBar: topBar,
            projects: navigation.projects,
            sidebar: navigation.sidebar,
            transcript: TranscriptSurface(
                messages: thread.map { WorkspaceTranscriptSurfaceBuilder(thread: $0).messageSurfaces() } ?? [],
                toolCards: toolCards,
                timelineItems: thread == nil ? nil : currentTimelineItems,
                thinking: WorkspaceTranscriptThinkingSurfaceBuilder(
                    thread: thread,
                    composer: composer,
                    agentStatus: topBarState.agentStatus
                ).surface()
            ),
            contextBanner: WorkspaceContextBannerBuilder(thread: thread).banner(),
            review: WorkspaceReviewSurfaceBuilder(
                toolCards: toolCards,
                events: thread?.events ?? []
            ).surface(),
            terminal: TerminalSurface(
                terminal: terminal,
                cwd: terminalCurrentDirectoryURL
            ),
            browser: BrowserSurface(browser: browser),
            extensions: WorkspaceExtensionsSurface(
                isVisible: extensions.isVisible,
                manifests: selectedProject?.extensionManifests ?? [],
                mcpServerStatuses: extensions.mcpServerStatuses,
                mcpServerProbeSummaries: extensions.mcpServerProbeSummaries
            ),
            memories: WorkspaceMemoriesSurface(
                isVisible: memories.isVisible,
                notes: activeSources.memories,
                canEditProjectMemories: canEditProjectMemories
            ),
            activity: WorkspaceActivitySurface(
                isVisible: activity.isVisible,
                thread: thread,
                toolCards: toolCards,
                instructions: activeSources.instructions,
                memories: activeSources.memories,
                agentStatus: topBarState.agentStatus,
                collapsedSectionIDs: activity.collapsedSectionIDs
            ),
            automations: WorkspaceAutomationsSurfaceBuilder(
                isVisible: automations.isVisible,
                automations: automations.items,
                hasSelectedThread: thread != nil,
                hasSelectedProject: selectedProject != nil
            ).surface(),
            composer: ComposerSurface(composer: composer),
            commands: commandSurfaceBuilder().commands,
            settings: WorkspaceSettingsSurface(
                config: root.config,
                hasStoredAPIKey: root.trustedRouterAPIKeyConfigured,
                runtimeIssue: runtimeIssue,
                computerUseStatus: computerUse
            ),
            runtimeIssue: runtimeIssue,
            lastError: lastError
        )
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
        return WorkspaceCommandSurfaceBuilder(
            selectedThread: selectedThread,
            selectedProject: selectedProject,
            selectedSidebarThreads: selectedSidebarThreads,
            sidebarSelectionIsActive: sidebarSelection.isActive,
            sidebarItemCount: visibleSidebarItemCount,
            hasActiveWorkspaceRoot: activeWorkspaceRoot != nil,
            canRetryLastUserTurn: canRetryLastUserTurn,
            composerIsSending: composer.isSending,
            terminalHasEntries: !terminal.entries.isEmpty,
            terminalIsRunning: terminal.isRunning,
            browserCanGoBack: browser.canGoBack,
            browserCanGoForward: browser.canGoForward,
            browserCanReload: browser.canReload,
            browserCanOpenSession: browser.currentURL != nil
                || !browser.addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            mcpServerStatuses: extensions.mcpServerStatuses,
            mcpServerProbeSummaries: extensions.mcpServerProbeSummaries,
            computerUseStatus: root.topBar.computerUseStatus
        )
    }

}
