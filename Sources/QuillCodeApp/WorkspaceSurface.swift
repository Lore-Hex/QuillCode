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

public enum RuntimeIssueSeverity: String, Codable, Sendable, Hashable {
    case info
    case warning
    case error
}

public enum ExecutionContextKind: String, Codable, Sendable, Hashable {
    case local
    case sshRemote = "ssh-remote"
}

public struct ExecutionContextSurface: Codable, Sendable, Hashable {
    public var kind: ExecutionContextKind
    public var label: String
    public var detail: String

    public init(kind: ExecutionContextKind, label: String, detail: String) {
        self.kind = kind
        self.label = label
        self.detail = detail
    }

    public static func local(path: String?) -> ExecutionContextSurface {
        let detail: String
        if let path, !path.isEmpty {
            detail = path
        } else {
            detail = "No project"
        }
        return ExecutionContextSurface(
            kind: .local,
            label: "Local",
            detail: detail
        )
    }

    public static func project(_ project: ProjectRef) -> ExecutionContextSurface {
        switch project.connection.kind {
        case .local:
            return .local(path: project.displayPath)
        case .ssh:
            let host = project.connection.host ?? "ssh"
            return ExecutionContextSurface(
                kind: .sshRemote,
                label: "SSH Remote",
                detail: host
            )
        }
    }
}

public struct RuntimeIssueSurface: Codable, Sendable, Hashable {
    public var severity: RuntimeIssueSeverity
    public var title: String
    public var message: String
    public var actionLabel: String?
    public var diagnostics: [RuntimeDiagnosticSurface]

    public init(
        severity: RuntimeIssueSeverity,
        title: String,
        message: String,
        actionLabel: String? = nil,
        diagnostics: [RuntimeDiagnosticSurface] = []
    ) {
        self.severity = severity
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case severity
        case title
        case message
        case actionLabel
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.severity = try container.decode(RuntimeIssueSeverity.self, forKey: .severity)
        self.title = try container.decode(String.self, forKey: .title)
        self.message = try container.decode(String.self, forKey: .message)
        self.actionLabel = try container.decodeIfPresent(String.self, forKey: .actionLabel)
        self.diagnostics = try container.decodeIfPresent([RuntimeDiagnosticSurface].self, forKey: .diagnostics) ?? []
    }

    func withDiagnostics(_ diagnostics: [RuntimeDiagnosticSurface]) -> RuntimeIssueSurface {
        var copy = self
        copy.diagnostics = diagnostics
        return copy
    }
}

public struct RuntimeDiagnosticSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ProjectListSurface: Codable, Sendable, Hashable {
    public var title: String
    public var items: [ProjectItemSurface]
    public var selectedProjectID: UUID?
    public var emptyTitle: String

    public init(
        title: String = "Projects",
        items: [ProjectItemSurface],
        selectedProjectID: UUID?,
        emptyTitle: String = "No projects yet"
    ) {
        self.title = title
        self.items = items
        self.selectedProjectID = selectedProjectID
        self.emptyTitle = emptyTitle
    }
}

public struct ProjectItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String
    public var connectionKindLabel: String
    public var isRemote: Bool
    public var actions: [ProjectItemActionSurface]
    public var isSelected: Bool

    public init(project: ProjectRef, selectedProjectID: UUID?) {
        self.id = project.id
        self.name = project.name
        self.path = project.displayPath
        self.connectionKindLabel = project.connection.kindLabel
        self.isRemote = project.isRemote
        self.actions = [
            ProjectItemActionSurface(kind: .newChat, projectID: project.id),
            ProjectItemActionSurface(kind: .refreshContext, projectID: project.id),
            ProjectItemActionSurface(kind: .rename, projectID: project.id),
            ProjectItemActionSurface(kind: .remove, projectID: project.id)
        ]
        self.isSelected = project.id == selectedProjectID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case connectionKindLabel
        case isRemote
        case actions
        case isSelected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.connectionKindLabel = try container.decodeIfPresent(String.self, forKey: .connectionKindLabel) ?? "Local"
        self.isRemote = try container.decodeIfPresent(Bool.self, forKey: .isRemote) ?? false
        self.actions = try container.decodeIfPresent([ProjectItemActionSurface].self, forKey: .actions) ?? [
            ProjectItemActionSurface(kind: .newChat, projectID: id),
            ProjectItemActionSurface(kind: .refreshContext, projectID: id),
            ProjectItemActionSurface(kind: .rename, projectID: id),
            ProjectItemActionSurface(kind: .remove, projectID: id)
        ]
        self.isSelected = try container.decode(Bool.self, forKey: .isSelected)
    }
}

public enum ProjectItemActionKind: String, Codable, Sendable, Hashable {
    case newChat
    case refreshContext
    case rename
    case remove

    public var title: String {
        switch self {
        case .newChat:
            return "New chat"
        case .refreshContext:
            return "Refresh context"
        case .rename:
            return "Rename"
        case .remove:
            return "Remove from list"
        }
    }
}

public struct ProjectItemActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: ProjectItemActionKind
    public var projectID: UUID
    public var isEnabled: Bool
    public var disabledReason: String?

    public var id: String {
        "\(projectID.uuidString)-\(kind.rawValue)"
    }

    public init(
        kind: ProjectItemActionKind,
        projectID: UUID,
        isEnabled: Bool = true,
        disabledReason: String? = nil
    ) {
        self.kind = kind
        self.projectID = projectID
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case projectID
        case isEnabled
        case disabledReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(ProjectItemActionKind.self, forKey: .kind)
        self.projectID = try container.decode(UUID.self, forKey: .projectID)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.disabledReason = try container.decodeIfPresent(String.self, forKey: .disabledReason)
    }
}

public struct SidebarSurface: Codable, Sendable, Hashable {
    public var title: String
    public var items: [SidebarItemSurface]
    public var selectedThreadID: UUID?
    public var emptyTitle: String
    public var isSelectionMode: Bool
    public var selectedThreadIDs: Set<UUID>
    public var selectionLabel: String
    public var bulkActions: [SidebarBulkActionSurface]

    public init(
        title: String = "Chats",
        items: [SidebarItemSurface],
        selectedThreadID: UUID?,
        emptyTitle: String = "No chats yet",
        isSelectionMode: Bool = false,
        selectedThreadIDs: Set<UUID> = [],
        bulkActions: [SidebarBulkActionSurface] = []
    ) {
        self.title = title
        self.items = items
        self.selectedThreadID = selectedThreadID
        self.emptyTitle = emptyTitle
        self.isSelectionMode = isSelectionMode
        self.selectedThreadIDs = selectedThreadIDs
        self.selectionLabel = Self.selectionLabel(count: selectedThreadIDs.count)
        self.bulkActions = bulkActions
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case items
        case selectedThreadID
        case emptyTitle
        case isSelectionMode
        case selectedThreadIDs
        case selectionLabel
        case bulkActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Chats"
        self.items = try container.decodeIfPresent([SidebarItemSurface].self, forKey: .items) ?? []
        self.selectedThreadID = try container.decodeIfPresent(UUID.self, forKey: .selectedThreadID)
        self.emptyTitle = try container.decodeIfPresent(String.self, forKey: .emptyTitle) ?? "No chats yet"
        self.isSelectionMode = try container.decodeIfPresent(Bool.self, forKey: .isSelectionMode) ?? false
        self.selectedThreadIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .selectedThreadIDs) ?? []
        self.selectionLabel = try container.decodeIfPresent(String.self, forKey: .selectionLabel)
            ?? Self.selectionLabel(count: self.selectedThreadIDs.count)
        self.bulkActions = try container.decodeIfPresent([SidebarBulkActionSurface].self, forKey: .bulkActions) ?? []
    }

    public func filteredItems(matching query: String) -> [SidebarItemSurface] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return items
        }
        return items.filter { item in
            let pinLabel = item.isPinned ? "pinned" : ""
            let archivedLabel = item.isArchived ? "archived" : ""
            return item.title.localizedCaseInsensitiveContains(normalizedQuery)
                || item.subtitle.localizedCaseInsensitiveContains(normalizedQuery)
                || item.searchText.localizedCaseInsensitiveContains(normalizedQuery)
                || pinLabel.localizedCaseInsensitiveContains(normalizedQuery)
                || archivedLabel.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    public var pinnedItems: [SidebarItemSurface] {
        items.filter { $0.isPinned && !$0.isArchived }
    }

    public var recentItems: [SidebarItemSurface] {
        items.filter { !$0.isPinned && !$0.isArchived }
    }

    public var archivedItems: [SidebarItemSurface] {
        items.filter(\.isArchived)
    }

    private static func selectionLabel(count: Int) -> String {
        switch count {
        case 0:
            return "No chats selected"
        case 1:
            return "1 chat selected"
        default:
            return "\(count) chats selected"
        }
    }
}

public struct SidebarItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var searchText: String
    public var actions: [SidebarItemActionSurface]
    public var isSelected: Bool
    public var isBulkSelected: Bool
    public var isPinned: Bool
    public var isArchived: Bool

    public init(item: SidebarItem, selectedThreadID: UUID?, selectedThreadIDs: Set<UUID> = []) {
        self.id = item.id
        self.title = item.title
        self.subtitle = item.subtitle
        self.searchText = item.searchText
        self.actions = Self.actions(for: item)
        self.isSelected = item.id == selectedThreadID
        self.isBulkSelected = selectedThreadIDs.contains(item.id)
        self.isPinned = item.isPinned
        self.isArchived = item.isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case searchText
        case actions
        case isSelected
        case isBulkSelected
        case isPinned
        case isArchived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.searchText = try container.decode(String.self, forKey: .searchText)
        self.actions = try container.decodeIfPresent([SidebarItemActionSurface].self, forKey: .actions) ?? []
        self.isSelected = try container.decode(Bool.self, forKey: .isSelected)
        self.isBulkSelected = try container.decodeIfPresent(Bool.self, forKey: .isBulkSelected) ?? false
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(searchText, forKey: .searchText)
        try container.encode(actions, forKey: .actions)
        try container.encode(isSelected, forKey: .isSelected)
        try container.encode(isBulkSelected, forKey: .isBulkSelected)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
    }

    private static func actions(for item: SidebarItem) -> [SidebarItemActionSurface] {
        if item.isArchived {
            return [
                SidebarItemActionSurface(kind: .unarchive, threadID: item.id),
                SidebarItemActionSurface(kind: .delete, threadID: item.id)
            ]
        }
        return [
            SidebarItemActionSurface(kind: .rename, threadID: item.id),
            SidebarItemActionSurface(kind: .duplicate, threadID: item.id),
            SidebarItemActionSurface(
                kind: item.isPinned ? .unpin : .pin,
                threadID: item.id
            ),
            SidebarItemActionSurface(kind: .archive, threadID: item.id),
            SidebarItemActionSurface(kind: .delete, threadID: item.id)
        ]
    }
}

public enum SidebarBulkActionKind: String, Codable, Sendable, Hashable {
    case select
    case selectAll
    case clearSelection
    case pin
    case unpin
    case archive
    case unarchive
    case delete

    public var title: String {
        switch self {
        case .select:
            return "Select"
        case .selectAll:
            return "Select all"
        case .clearSelection:
            return "Done"
        case .pin:
            return "Pin"
        case .unpin:
            return "Unpin"
        case .archive:
            return "Archive"
        case .unarchive:
            return "Unarchive"
        case .delete:
            return "Delete"
        }
    }
}

public struct SidebarBulkActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: SidebarBulkActionKind
    public var commandID: String
    public var title: String
    public var isEnabled: Bool
    public var isDestructive: Bool

    public var id: String { commandID }

    public init(
        kind: SidebarBulkActionKind,
        isEnabled: Bool = true,
        isDestructive: Bool = false
    ) {
        self.kind = kind
        self.commandID = Self.commandID(for: kind)
        self.title = kind.title
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
    }

    public static func commandID(for kind: SidebarBulkActionKind) -> String {
        switch kind {
        case .select:
            return "thread-selection-start"
        case .selectAll:
            return "thread-selection-select-all"
        case .clearSelection:
            return "thread-selection-clear"
        case .pin:
            return "thread-bulk-pin"
        case .unpin:
            return "thread-bulk-unpin"
        case .archive:
            return "thread-bulk-archive"
        case .unarchive:
            return "thread-bulk-unarchive"
        case .delete:
            return "thread-bulk-delete"
        }
    }
}

public enum SidebarItemActionKind: String, Codable, Sendable, Hashable {
    case rename
    case duplicate
    case pin
    case unpin
    case archive
    case unarchive
    case delete

    public var title: String {
        switch self {
        case .rename:
            return "Rename"
        case .duplicate:
            return "Duplicate"
        case .pin:
            return "Pin"
        case .unpin:
            return "Unpin"
        case .archive:
            return "Archive"
        case .unarchive:
            return "Unarchive"
        case .delete:
            return "Delete"
        }
    }
}

public struct SidebarItemActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: SidebarItemActionKind
    public var threadID: UUID

    public var id: String {
        "\(threadID.uuidString)-\(kind.rawValue)"
    }

    public init(kind: SidebarItemActionKind, threadID: UUID) {
        self.kind = kind
        self.threadID = threadID
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
                subtitle: topBarSubtitle(thread: thread),
                instructionLabel: Self.instructionStatusLabel(for: activeInstructions),
                instructionSources: activeInstructions.map(\.path),
                memoryLabel: Self.memoryStatusLabel(for: activeMemories),
                memorySources: activeMemories.map(\.relativePath),
                modelLabel: modelCatalog.modelLabel(),
                selectedModelID: topBarState.model,
                modelCategories: modelCatalog.categories(),
                modeLabel: Self.modeLabel(topBarState.mode),
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

    private func topBarSubtitle(thread: ChatThread?) -> String {
        let projectName = root.topBar.projectName ?? "No project"
        guard let thread else {
            return "\(projectName) - Not started"
        }
        return "\(projectName) - \(Self.modeLabel(thread.mode)) - \(thread.model)"
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

    static func modeLabel(_ mode: AgentMode) -> String {
        switch mode {
        case .readOnly:
            return "Read-only"
        case .review:
            return "Review"
        case .auto:
            return "Auto"
        }
    }
}
