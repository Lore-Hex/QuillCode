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
        let activeInstructions: [ProjectInstruction]
        if let thread, !thread.instructions.isEmpty {
            activeInstructions = thread.instructions
        } else {
            activeInstructions = selectedProject?.instructions ?? []
        }
        let activeMemories: [MemoryNote]
        if let thread, !thread.memories.isEmpty {
            activeMemories = thread.memories
        } else {
            activeMemories = root.globalMemories + (selectedProject?.memories ?? [])
        }
        let sidebarSelectedThreadIDs = sidebarSelection.isActive
            ? Set(selectedSidebarThreadIDs())
            : []
        let modelCatalog = modelCatalogBuilder(selectedModelID: topBarState.model)
        return WorkspaceSurface(
            topBar: TopBarSurface(
                appName: topBarState.appName,
                primaryTitle: thread?.title ?? "QuillCode",
                subtitle: WorkspaceStatusTextBuilder.topBarSubtitle(
                    projectName: root.topBar.projectName ?? "No project",
                    thread: thread
                ),
                instructionLabel: WorkspaceStatusTextBuilder.instructionLabel(for: activeInstructions),
                instructionSources: activeInstructions.map(\.path),
                memoryLabel: WorkspaceStatusTextBuilder.memoryLabel(for: activeMemories),
                memorySources: activeMemories.map(\.relativePath),
                modelLabel: modelCatalog.modelLabel(),
                selectedModelID: topBarState.model,
                modelCategories: modelCatalog.categories(),
                modeLabel: WorkspaceStatusTextBuilder.modeLabel(topBarState.mode),
                agentStatus: topBarState.agentStatus,
                runtimeIssueLabel: runtimeIssue?.title,
                runtimeIssueSeverity: runtimeIssue?.severity,
                computerUseLabel: computerUse.message,
                showsComputerUseSetup: !computerUse.available
            ),
            projects: ProjectListSurface(
                items: projectItems(),
                selectedProjectID: root.selectedProjectID
            ),
            sidebar: SidebarSurface(
                items: root.allSidebarItems.map {
                    SidebarItemSurface(
                        item: $0,
                        selectedThreadID: root.selectedThreadID,
                        selectedThreadIDs: sidebarSelectedThreadIDs
                    )
                },
                selectedThreadID: root.selectedThreadID,
                isSelectionMode: sidebarSelection.isActive,
                selectedThreadIDs: sidebarSelectedThreadIDs,
                bulkActions: sidebarBulkActions(selectedThreadIDs: sidebarSelectedThreadIDs)
            ),
            transcript: TranscriptSurface(
                messages: thread.map { WorkspaceTranscriptSurfaceBuilder(thread: $0).messageSurfaces() } ?? [],
                toolCards: toolCards,
                timelineItems: thread == nil ? nil : currentTimelineItems
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
                notes: activeMemories
            ),
            activity: WorkspaceActivitySurface(
                isVisible: activity.isVisible,
                thread: thread,
                toolCards: toolCards,
                instructions: activeInstructions,
                memories: activeMemories,
                agentStatus: topBarState.agentStatus,
                collapsedSectionIDs: activity.collapsedSectionIDs
            ),
            automations: WorkspaceAutomationsSurface(
                isVisible: automations.isVisible,
                automations: automations.items,
                createThreadFollowUpCommand: .automationCreateThreadFollowUp(
                    isEnabled: thread != nil
                ),
                createWorkspaceScheduleCommand: .automationCreateWorkspaceSchedule(
                    isEnabled: selectedProject != nil
                ),
                scheduleThreadFollowUpCommands: WorkspaceCommandSurface.automationScheduleThreadFollowUpCommands(
                    isEnabled: thread != nil
                ),
                scheduleWorkspaceScheduleCommands: WorkspaceCommandSurface.automationScheduleWorkspaceScheduleCommands(
                    isEnabled: selectedProject != nil
                )
            ),
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

    private func sidebarBulkActions(selectedThreadIDs: Set<UUID>) -> [SidebarBulkActionSurface] {
        let selectedThreads = root.threads.filter { selectedThreadIDs.contains($0.id) }
        let hasSelection = !selectedThreads.isEmpty
        guard sidebarSelection.isActive else {
            return [
                SidebarBulkActionSurface(
                    kind: .select,
                    isEnabled: !root.threads.isEmpty
                )
            ]
        }

        let hasPinnedSelection = selectedThreads.contains { $0.isPinned }
        let hasUnarchivedSelection = selectedThreads.contains { !$0.isArchived }
        let hasArchivedSelection = selectedThreads.contains { $0.isArchived }
        return [
            SidebarBulkActionSurface(kind: .clearSelection),
            SidebarBulkActionSurface(
                kind: .selectAll,
                isEnabled: selectedThreadIDs.count < root.allSidebarItems.count
            ),
            SidebarBulkActionSurface(
                kind: .pin,
                isEnabled: hasUnarchivedSelection
            ),
            SidebarBulkActionSurface(
                kind: .unpin,
                isEnabled: hasPinnedSelection
            ),
            SidebarBulkActionSurface(
                kind: .archive,
                isEnabled: hasUnarchivedSelection
            ),
            SidebarBulkActionSurface(
                kind: .unarchive,
                isEnabled: hasArchivedSelection
            ),
            SidebarBulkActionSurface(
                kind: .delete,
                isEnabled: hasSelection,
                isDestructive: true
            )
        ]
    }

    private func projectItems() -> [ProjectItemSurface] {
        root.projects
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .map { ProjectItemSurface(project: $0, selectedProjectID: root.selectedProjectID) }
    }

    private func modelCatalogBuilder(selectedModelID: String) -> WorkspaceModelCatalogSurfaceBuilder {
        let recentModelIDs = root.threads
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.model)
        return WorkspaceModelCatalogSurfaceBuilder(
            catalog: root.modelCatalog,
            selectedModelID: selectedModelID,
            defaultModelID: root.config.defaultModel,
            favoriteModelIDs: root.config.favoriteModels,
            recentModelIDs: recentModelIDs
        )
    }

    private func commandSurfaceBuilder() -> WorkspaceCommandSurfaceBuilder {
        let sidebarSelectedThreadIDs = Set(selectedSidebarThreadIDs())
        let selectedSidebarThreads = root.threads.filter { sidebarSelectedThreadIDs.contains($0.id) }
        return WorkspaceCommandSurfaceBuilder(
            selectedThread: selectedThread,
            selectedProject: selectedProject,
            selectedSidebarThreads: selectedSidebarThreads,
            sidebarSelectionIsActive: sidebarSelection.isActive,
            sidebarItemCount: root.allSidebarItems.count,
            hasActiveWorkspaceRoot: activeWorkspaceRoot != nil,
            canRetryLastUserTurn: canRetryLastUserTurn,
            composerIsSending: composer.isSending,
            terminalHasEntries: !terminal.entries.isEmpty,
            terminalIsRunning: terminal.isRunning,
            browserCanGoBack: browser.canGoBack,
            browserCanGoForward: browser.canGoForward,
            browserCanReload: browser.canReload,
            mcpServerStatuses: extensions.mcpServerStatuses,
            computerUseStatus: root.topBar.computerUseStatus
        )
    }

}
