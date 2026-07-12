import Foundation
import QuillCodeCore
import QuillComputerUseKit

struct WorkspaceCommandSurfaceBuilder: Sendable, Hashable {
    var selectedThread: ChatThread?
    var selectedProject: ProjectRef?
    var selectedSidebarThreads: [ChatThread]
    var sidebarSelectionIsActive: Bool
    var sidebarItemCount: Int
    var sidebarSavedSearches: [SidebarSavedSearch] = []
    var hasActiveWorkspaceRoot: Bool
    var canRetryLastUserTurn: Bool
    var composerIsSending: Bool
    var terminalHasEntries: Bool
    var terminalIsRunning: Bool
    var browserCanGoBack: Bool
    var browserCanGoForward: Bool
    var browserCanReload: Bool
    var browserCanOpenSession: Bool
    var canNavigateBack: Bool = false
    var canNavigateForward: Bool = false
    var mcpServerStatuses: [String: MCPServerLifecycleStatus]
    var mcpServerProbeSummaries: [String: MCPServerProbeSummary]
    var computerUseStatus: ComputerUseStatus
    var selectedThreadIsRunning: Bool = false
    var runningThreadIDs: Set<UUID> = []

    var commands: [WorkspaceCommandSurface] {
        WorkspaceThreadCommandCatalog.commands(
            availability: threadAvailability,
            savedSearches: sidebarSavedSearches
        )
        + WorkspaceCommandStaticCatalog.retryCommands(
            canRetryLastUserTurn: canRetryLastUserTurn
        )
        + WorkspaceCommandStaticCatalog.navigationCommands(
            hasSelectedThread: hasSelectedThread,
            canNavigateBack: canNavigateBack,
            canNavigateForward: canNavigateForward
        )
        + WorkspaceCommandStaticCatalog.workspaceCommands(
            hasSelectedProject: hasSelectedProject,
            terminalHasEntries: terminalHasEntries,
            terminalIsRunning: terminalIsRunning,
            browserCanGoBack: browserCanGoBack,
            browserCanGoForward: browserCanGoForward,
            browserCanReload: browserCanReload,
            browserCanOpenSession: browserCanOpenSession
        )
        + WorkspaceCommandStaticCatalog.automationCommands(
            hasSelectedThread: hasSelectedThread,
            hasSelectedProject: hasSelectedProject
        )
        + WorkspaceCommandStaticCatalog.memoryCommands()
        + WorkspaceCommandStaticCatalog.extensionToggleCommands(
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
        + WorkspaceGitCommandCatalog.commands(
            hasWorkspaceOrRemoteProject: hasWorkspaceOrRemoteProject
        )
        + WorkspaceProjectCommandCatalog.localActionCommands(
            actions: selectedProject?.localActions ?? [],
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
        + WorkspaceProjectCommandCatalog.mcpLifecycleCommands(
            manifests: selectedProject?.extensionManifests ?? [],
            statuses: mcpServerStatuses,
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
        + WorkspaceProjectCommandCatalog.mcpReferenceCommands(
            manifests: selectedProject?.extensionManifests ?? [],
            statuses: mcpServerStatuses,
            probeSummaries: mcpServerProbeSummaries,
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
        + WorkspaceProjectCommandCatalog.extensionInstallCommands(
            manifests: selectedProject?.extensionManifests ?? [],
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
        + WorkspaceProjectCommandCatalog.extensionUpdateCommands(
            manifests: selectedProject?.extensionManifests ?? [],
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
        + WorkspaceCommandStaticCatalog.controlAndSettingsCommands(
            composerIsSending: composerIsSending,
            terminalIsRunning: terminalIsRunning,
            hasActiveMCPServer: mcpServerStatuses.values.contains { $0.isActive },
            hasSelectedRemoteProject: selectedProjectIsRemote
        )
        + WorkspaceCommandStaticCatalog.computerUseCommands(
            computerUseStatus: computerUseStatus
        )
    }

    private var hasSelectedThread: Bool {
        selectedThread != nil
    }

    private var hasSelectedProject: Bool {
        selectedProject != nil
    }

    private var selectedThreadHasMessages: Bool {
        selectedThread?.messages.isEmpty == false
    }

    private var selectedThreadCanClear: Bool {
        guard let selectedThread, !selectedThreadIsRunning else { return false }
        return !selectedThread.messages.isEmpty
            || !selectedThread.events.isEmpty
            || !selectedThread.followUpQueue.isEmpty
    }

    private var selectedThreadCanRevertLatestTurn: Bool {
        guard let selectedThread, !selectedProjectIsRemote, !selectedThreadIsRunning else { return false }
        return WorkspaceTurnRevertPlanner.latestPlan(in: selectedThread) != nil
    }

    private var selectedThreadCanPin: Bool {
        guard let selectedThread else { return false }
        return !selectedThread.isPinned && !selectedThread.isArchived
    }

    private var selectedThreadCanUnpin: Bool {
        selectedThread?.isPinned == true
    }

    private var selectedThreadHandoffTitle: String? {
        guard !composerIsSending,
              !selectedThreadIsRunning,
              !terminalIsRunning,
              selectedProject != nil,
              selectedProjectIsRemote == false,
              selectedThread?.isArchived == false,
              let worktree = selectedThread?.worktree,
              worktree.isResolvable,
              worktree.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return worktree.location == .worktree ? "Hand off to Local" : "Hand off to Worktree"
    }

    private var selectedProjectIsRemote: Bool {
        selectedProject?.isRemote == true
    }

    private var hasWorkspaceOrRemoteProject: Bool {
        hasActiveWorkspaceRoot || selectedProjectIsRemote
    }

    private var threadAvailability: WorkspaceThreadCommandAvailability {
        WorkspaceThreadCommandAvailability(
            hasSelectedThread: hasSelectedThread,
            selectedThreadIsArchived: selectedThread?.isArchived == true,
            selectedThreadHasMessages: selectedThreadHasMessages && !selectedThreadIsRunning,
            selectedThreadCanClear: selectedThreadCanClear,
            selectedThreadCanRevertLatestTurn: selectedThreadCanRevertLatestTurn,
            selectedThreadCanPin: selectedThreadCanPin,
            selectedThreadCanUnpin: selectedThreadCanUnpin,
            selectedThreadIsRunning: selectedThreadIsRunning,
            selectedThreadHandoffTitle: selectedThreadHandoffTitle,
            hasAnySidebarThread: sidebarItemCount > 0,
            sidebarSelectionIsActive: sidebarSelectionIsActive,
            hasSidebarSelection: !selectedSidebarThreads.isEmpty,
            hasPinnedSidebarSelection: selectedSidebarThreads.contains { $0.isPinned },
            hasUnpinnedUnarchivedSidebarSelection: selectedSidebarThreads.contains { !$0.isPinned && !$0.isArchived },
            hasUnarchivedSidebarSelection: selectedSidebarThreads.contains { !$0.isArchived },
            hasArchivedSidebarSelection: selectedSidebarThreads.contains { $0.isArchived },
            hasRunningSidebarSelection: selectedSidebarThreads.contains { runningThreadIDs.contains($0.id) }
        )
    }
}
