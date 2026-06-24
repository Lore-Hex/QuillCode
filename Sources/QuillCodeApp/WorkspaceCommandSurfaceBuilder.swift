import Foundation
import QuillCodeCore
import QuillComputerUseKit

struct WorkspaceCommandSurfaceBuilder: Sendable, Hashable {
    var selectedThread: ChatThread?
    var selectedProject: ProjectRef?
    var selectedSidebarThreads: [ChatThread]
    var sidebarSelectionIsActive: Bool
    var sidebarItemCount: Int
    var hasActiveWorkspaceRoot: Bool
    var canRetryLastUserTurn: Bool
    var composerIsSending: Bool
    var terminalHasEntries: Bool
    var terminalIsRunning: Bool
    var browserCanGoBack: Bool
    var browserCanGoForward: Bool
    var browserCanReload: Bool
    var mcpServerStatuses: [String: MCPServerLifecycleStatus]
    var computerUseStatus: ComputerUseStatus

    var commands: [WorkspaceCommandSurface] {
        WorkspaceThreadCommandCatalog.commands(
            availability: threadAvailability
        )
        + WorkspaceCommandStaticCatalog.retryCommands(
            canRetryLastUserTurn: canRetryLastUserTurn
        )
        + WorkspaceCommandStaticCatalog.navigationCommands(
            hasSelectedThread: hasSelectedThread
        )
        + WorkspaceCommandStaticCatalog.workspaceCommands(
            hasSelectedProject: hasSelectedProject,
            terminalHasEntries: terminalHasEntries,
            terminalIsRunning: terminalIsRunning,
            browserCanGoBack: browserCanGoBack,
            browserCanGoForward: browserCanGoForward,
            browserCanReload: browserCanReload
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
        + WorkspaceProjectCommandCatalog.extensionUpdateCommands(
            manifests: selectedProject?.extensionManifests ?? [],
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
        + WorkspaceCommandStaticCatalog.controlAndSettingsCommands(
            composerIsSending: composerIsSending,
            terminalIsRunning: terminalIsRunning,
            hasActiveMCPServer: mcpServerStatuses.values.contains { $0.isActive }
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
            selectedThreadHasMessages: selectedThreadHasMessages,
            hasAnySidebarThread: sidebarItemCount > 0,
            sidebarSelectionIsActive: sidebarSelectionIsActive,
            hasSidebarSelection: !selectedSidebarThreads.isEmpty,
            hasPinnedSidebarSelection: selectedSidebarThreads.contains { $0.isPinned },
            hasUnarchivedSidebarSelection: selectedSidebarThreads.contains { !$0.isArchived },
            hasArchivedSidebarSelection: selectedSidebarThreads.contains { $0.isArchived }
        )
    }
}
