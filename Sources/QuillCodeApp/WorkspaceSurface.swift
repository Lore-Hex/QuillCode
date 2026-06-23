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

public struct TopBarSurface: Codable, Sendable, Hashable {
    public var appName: String
    public var primaryTitle: String
    public var subtitle: String
    public var instructionLabel: String
    public var instructionSources: [String]
    public var memoryLabel: String
    public var memorySources: [String]
    public var modelLabel: String
    public var selectedModelID: String
    public var modelCategories: [ModelCategorySurface]
    public var modeLabel: String
    public var agentStatus: String
    public var runtimeIssueLabel: String?
    public var runtimeIssueSeverity: RuntimeIssueSeverity?
    public var computerUseLabel: String
    public var showsComputerUseSetup: Bool

    public init(
        appName: String,
        primaryTitle: String,
        subtitle: String,
        instructionLabel: String,
        instructionSources: [String],
        memoryLabel: String,
        memorySources: [String],
        modelLabel: String,
        selectedModelID: String,
        modelCategories: [ModelCategorySurface],
        modeLabel: String,
        agentStatus: String,
        runtimeIssueLabel: String? = nil,
        runtimeIssueSeverity: RuntimeIssueSeverity? = nil,
        computerUseLabel: String,
        showsComputerUseSetup: Bool
    ) {
        self.appName = appName
        self.primaryTitle = primaryTitle
        self.subtitle = subtitle
        self.instructionLabel = instructionLabel
        self.instructionSources = instructionSources
        self.memoryLabel = memoryLabel
        self.memorySources = memorySources
        self.modelLabel = modelLabel
        self.selectedModelID = selectedModelID
        self.modelCategories = modelCategories
        self.modeLabel = modeLabel
        self.agentStatus = agentStatus
        self.runtimeIssueLabel = runtimeIssueLabel
        self.runtimeIssueSeverity = runtimeIssueSeverity
        self.computerUseLabel = computerUseLabel
        self.showsComputerUseSetup = showsComputerUseSetup
    }

    public func filteredModelCategories(matching query: String) -> [ModelCategorySurface] {
        let normalizedTerms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !normalizedTerms.isEmpty else {
            return modelCategories
        }

        let includesFavoriteTerm = normalizedTerms.contains("favorite") || normalizedTerms.contains("favorites")
        let includesRecentTerm = normalizedTerms.contains("recent")
        return modelCategories.compactMap { category in
            if includesFavoriteTerm && category.category != "Favorites" {
                return nil
            }
            if includesRecentTerm && category.category != "Recent" {
                return nil
            }
            if category.category == "Favorites" && !includesFavoriteTerm {
                return nil
            }
            if category.category == "Recent" && !includesRecentTerm {
                return nil
            }
            let models = category.models.filter { option in
                let haystack = [
                    category.category,
                    option.id,
                    option.provider,
                    option.displayName,
                    option.category,
                    option.detailTitle,
                    option.metadataSummary,
                    option.metadataDetails.joined(separator: " "),
                    option.metadataRows.map { row in
                        row.label == "State" ? "state \(row.value)" : row.value
                    }.joined(separator: " "),
                    option.badges.joined(separator: " ")
                ].joined(separator: " ").lowercased()
                return normalizedTerms.allSatisfy { haystack.contains($0) }
            }
            guard !models.isEmpty else { return nil }
            return ModelCategorySurface(category: category.category, models: models)
        }
    }
}

public struct ModelCategorySurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { category }
    public var category: String
    public var models: [ModelOptionSurface]

    public init(category: String, models: [ModelOptionSurface]) {
        self.category = category
        self.models = models
    }
}

public struct ModelMetadataRowSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ModelOptionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: String
    public var displayName: String
    public var category: String
    public var isSelected: Bool
    public var isFavorite: Bool
    public var badges: [String]
    public var metadataSummary: String
    public var metadataDetails: [String]
    public var detailTitle: String
    public var capabilitySummary: String
    public var metadataRows: [ModelMetadataRowSurface]
    public var modelInfo: ModelInfo {
        ModelInfo(id: id, provider: provider, displayName: displayName, category: category)
    }

    public init(model: ModelInfo, selectedModelID: String, isFavorite: Bool = false, badges: [String] = []) {
        self.id = model.id
        self.provider = model.provider
        self.displayName = model.displayName
        self.category = model.category
        self.isSelected = model.id == selectedModelID
        self.isFavorite = isFavorite
        self.badges = badges
        self.metadataSummary = Self.metadataSummary(modelID: model.id, category: model.category)
        self.detailTitle = Self.detailTitle(modelID: model.id, provider: model.provider, displayName: model.displayName)
        self.capabilitySummary = Self.capabilitySummary(modelID: model.id, category: model.category, badges: badges)
        self.metadataRows = Self.metadataRows(
            provider: model.provider,
            modelID: model.id,
            category: model.category,
            isSelected: model.id == selectedModelID,
            isFavorite: isFavorite,
            badges: badges
        )
        self.metadataDetails = Self.metadataDetails(
            provider: model.provider,
            modelID: model.id,
            category: model.category,
            isSelected: model.id == selectedModelID,
            isFavorite: isFavorite,
            badges: badges
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case displayName
        case category
        case isSelected
        case isFavorite
        case badges
        case metadataSummary
        case metadataDetails
        case detailTitle
        case capabilitySummary
        case metadataRows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.provider = try container.decode(String.self, forKey: .provider)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.category = try container.decode(String.self, forKey: .category)
        self.isSelected = try container.decode(Bool.self, forKey: .isSelected)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.badges = try container.decodeIfPresent([String].self, forKey: .badges) ?? []
        self.metadataSummary = try container.decodeIfPresent(String.self, forKey: .metadataSummary)
            ?? Self.metadataSummary(modelID: id, category: category)
        self.detailTitle = try container.decodeIfPresent(String.self, forKey: .detailTitle)
            ?? Self.detailTitle(modelID: id, provider: provider, displayName: displayName)
        self.capabilitySummary = try container.decodeIfPresent(String.self, forKey: .capabilitySummary)
            ?? Self.capabilitySummary(modelID: id, category: category, badges: badges)
        self.metadataRows = try container.decodeIfPresent([ModelMetadataRowSurface].self, forKey: .metadataRows)
            ?? Self.metadataRows(
                provider: provider,
                modelID: id,
                category: category,
                isSelected: isSelected,
                isFavorite: isFavorite,
                badges: badges
            )
        self.metadataDetails = try container.decodeIfPresent([String].self, forKey: .metadataDetails)
            ?? Self.metadataDetails(
                provider: provider,
                modelID: id,
                category: category,
                isSelected: isSelected,
                isFavorite: isFavorite,
                badges: badges
            )
    }

    private static func metadataSummary(modelID: String, category: String) -> String {
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(modelID)
        if canonicalModelID == TrustedRouterDefaults.defaultModel {
            return "Fast everyday agent"
        }
        if canonicalModelID == TrustedRouterDefaults.fusionModel {
            return "Deeper planning and review"
        }
        if category == TrustedRouterDefaults.safetyCategory {
            return "Auto safety reviewer"
        }
        return "\(category) model"
    }

    private static func detailTitle(modelID: String, provider: String, displayName: String) -> String {
        if let recommendedName = TrustedRouterDefaults.recommendedDisplayNames[TrustedRouterDefaults.canonicalModelID(modelID)] {
            return recommendedName
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }
        return modelID
    }

    private static func capabilitySummary(modelID: String, category: String, badges: [String]) -> String {
        if modelID == TrustedRouterDefaults.defaultModel {
            return "\(TrustedRouterDefaults.fastModelDisplayName) is the fast default for coding, shell, and file-editing turns."
        }
        if modelID == TrustedRouterDefaults.fusionModel {
            return "\(TrustedRouterDefaults.fusionModelDisplayName) is the balanced model for deeper coding and review turns."
        }
        if badges.contains("Recommended") {
            return "Recommended model profile available through TrustedRouter."
        }
        if category == "Safety" {
            return "Lightweight reviewer model for Auto safety decisions."
        }
        return "\(category) model available through TrustedRouter."
    }

    private static func metadataRows(
        provider: String,
        modelID: String,
        category: String,
        isSelected: Bool,
        isFavorite: Bool,
        badges: [String]
    ) -> [ModelMetadataRowSurface] {
        var state: [String] = []
        if isSelected {
            state.append("Current")
        }
        if badges.contains("Default") {
            state.append("Default")
        }
        if badges.contains("Recommended") {
            state.append("Recommended")
        }
        if isFavorite || badges.contains("Favorite") {
            state.append("Favorite")
        }
        if badges.contains("Recent") {
            state.append("Recent")
        }

        return [
            ModelMetadataRowSurface(label: "Provider", value: provider),
            ModelMetadataRowSurface(label: "Model ID", value: modelID),
            ModelMetadataRowSurface(label: "Category", value: category),
            ModelMetadataRowSurface(label: "State", value: state.isEmpty ? "Available" : unique(state).joined(separator: ", "))
        ]
    }

    private static func metadataDetails(
        provider: String,
        modelID: String,
        category: String,
        isSelected: Bool,
        isFavorite: Bool,
        badges: [String]
    ) -> [String] {
        var details = [
            "Provider: \(provider)",
            "Model ID: \(modelID)",
            "Category: \(category)"
        ]
        if isSelected {
            details.append("Current selection")
        }
        if isFavorite {
            details.append("Favorite")
        }
        for badge in badges {
            switch badge {
            case "Default":
                details.append("Default model")
            case "Recommended":
                details.append("Recommended by QuillCode")
            case "Recent":
                details.append("Recently used")
            case "Current", "Favorite":
                continue
            default:
                details.append(badge)
            }
        }
        return unique(details)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
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

public struct TranscriptSurface: Codable, Sendable, Hashable {
    public var messages: [MessageSurface]
    public var toolCards: [ToolCardState]
    public var timelineItems: [TranscriptTimelineItemSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    public init(
        messages: [MessageSurface],
        toolCards: [ToolCardState],
        timelineItems: [TranscriptTimelineItemSurface]? = nil,
        emptyTitle: String = "Ask QuillCode to inspect, edit, or run this project.",
        emptySubtitle: String = "Use Auto for normal coding work, Review for manual gates, or Read-only for exploration."
    ) {
        self.messages = messages
        self.toolCards = toolCards
        self.timelineItems = timelineItems ?? messages.map(TranscriptTimelineItemSurface.message)
            + toolCards.map(TranscriptTimelineItemSurface.toolCard)
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
    }
}

public enum TranscriptTimelineItemKind: String, Codable, Sendable {
    case message
    case toolCard
}

public struct TranscriptTimelineItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: TranscriptTimelineItemKind
    public var message: MessageSurface?
    public var toolCard: ToolCardState?

    public static func message(_ message: MessageSurface) -> TranscriptTimelineItemSurface {
        TranscriptTimelineItemSurface(
            id: "message-\(message.id.uuidString)",
            kind: .message,
            message: message
        )
    }

    public static func toolCard(_ toolCard: ToolCardState) -> TranscriptTimelineItemSurface {
        TranscriptTimelineItemSurface(
            id: "timeline-tool-\(toolCard.id)",
            kind: .toolCard,
            toolCard: toolCard
        )
    }
}

public struct ContextBannerSurface: Codable, Sendable, Hashable {
    public var usedPercent: Int
    public var title: String
    public var subtitle: String
    public var newThreadCommand: WorkspaceCommandSurface
    public var forkCommand: WorkspaceCommandSurface
    public var compactCommand: WorkspaceCommandSurface

    public init(
        usedPercent: Int,
        title: String,
        subtitle: String,
        newThreadCommand: WorkspaceCommandSurface,
        forkCommand: WorkspaceCommandSurface,
        compactCommand: WorkspaceCommandSurface = WorkspaceCommandSurface(
            id: "compact-context",
            title: "Compact context"
        )
    ) {
        self.usedPercent = usedPercent
        self.title = title
        self.subtitle = subtitle
        self.newThreadCommand = newThreadCommand
        self.forkCommand = forkCommand
        self.compactCommand = compactCommand
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case title
        case subtitle
        case newThreadCommand
        case forkCommand
        case compactCommand
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUsedPercent = try container.decode(Int.self, forKey: .usedPercent)
        let decodedTitle = try container.decode(String.self, forKey: .title)
        let decodedSubtitle = try container.decode(String.self, forKey: .subtitle)
        let decodedNewThreadCommand = try container.decode(WorkspaceCommandSurface.self, forKey: .newThreadCommand)
        let decodedForkCommand = try container.decode(WorkspaceCommandSurface.self, forKey: .forkCommand)
        let decodedCompactCommand = try container.decodeIfPresent(WorkspaceCommandSurface.self, forKey: .compactCommand)
            ?? WorkspaceCommandSurface(
                id: "compact-context",
                title: "Compact context",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "context", "summarize", "compact"],
                isEnabled: decodedForkCommand.isEnabled
            )
        self.usedPercent = decodedUsedPercent
        self.title = decodedTitle
        self.subtitle = decodedSubtitle
        self.newThreadCommand = decodedNewThreadCommand
        self.forkCommand = decodedForkCommand
        self.compactCommand = decodedCompactCommand
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(newThreadCommand, forKey: .newThreadCommand)
        try container.encode(forkCommand, forKey: .forkCommand)
        try container.encode(compactCommand, forKey: .compactCommand)
    }
}

public struct WorkspaceReviewSurface: Codable, Sendable, Hashable {
    public var title: String
    public var subtitle: String
    public var files: [WorkspaceReviewFileSurface]
    public var totalInsertions: Int
    public var totalDeletions: Int
    public var totalHunks: Int

    public var isVisible: Bool {
        !files.isEmpty
    }

    public init(
        title: String = "Review changes",
        subtitle: String = "Latest git diff",
        files: [WorkspaceReviewFileSurface] = []
    ) {
        self.title = title
        self.files = files
        self.totalInsertions = files.reduce(0) { $0 + $1.insertions }
        self.totalDeletions = files.reduce(0) { $0 + $1.deletions }
        self.totalHunks = files.reduce(0) { $0 + $1.hunks }
        self.subtitle = files.isEmpty
            ? subtitle
            : "\(files.count) file\(files.count == 1 ? "" : "s") changed, +\(totalInsertions) -\(totalDeletions)"
    }
}

public struct TerminalSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var draft: String
    public var isRunning: Bool
    public var cwdLabel: String
    public var entries: [TerminalCommandSurface]
    public var emptyTitle: String

    public var canRun: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning
    }

    public var canClear: Bool {
        !entries.isEmpty && !isRunning
    }

    public init(
        terminal: TerminalState,
        cwd: URL?,
        emptyTitle: String = "Run commands in this project without leaving QuillCode."
    ) {
        self.isVisible = terminal.isVisible
        self.draft = terminal.draft
        self.isRunning = terminal.isRunning
        self.cwdLabel = cwd?.path ?? terminal.currentDirectoryPath ?? "No project"
        self.entries = terminal.entries.map(TerminalCommandSurface.init)
        self.emptyTitle = emptyTitle
    }
}

public struct TerminalCommandSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var command: String
    public var stdout: String
    public var stderr: String
    public var exitCodeLabel: String
    public var statusLabel: String
    public var executionContext: ExecutionContextSurface?
    public var isSuccess: Bool
    public var isRunning: Bool
    public var isStopped: Bool

    public init(entry: TerminalCommandState) {
        self.id = entry.id
        self.command = entry.command
        self.stdout = entry.stdout
        self.stderr = entry.stderr
        self.exitCodeLabel = Self.exitCodeLabel(for: entry)
        self.statusLabel = Self.statusLabel(for: entry.status)
        self.executionContext = entry.executionContext
        self.isSuccess = entry.status == .done
        self.isRunning = entry.status == .running
        self.isStopped = entry.status == .stopped
    }

    private static func exitCodeLabel(for entry: TerminalCommandState) -> String {
        switch entry.status {
        case .running:
            return "running"
        case .stopped:
            return "stopped"
        case .done, .failed:
            return entry.exitCode.map { "exit \($0)" } ?? "exit unknown"
        }
    }

    private static func statusLabel(for status: TerminalCommandStatus) -> String {
        switch status {
        case .running:
            return "Running"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        case .stopped:
            return "Stopped"
        }
    }
}

public struct WorkspaceReviewCommentSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var path: String
    public var lineNumber: Int?
    public var endLineNumber: Int?
    public var lineKind: WorkspaceReviewLineKind?
    public var text: String
    public var createdAt: Date

    public var lineRangeLabel: String? {
        guard let lineNumber else { return nil }
        let endLineNumber = endLineNumber ?? lineNumber
        return lineNumber == endLineNumber
            ? "Line \(lineNumber)"
            : "Lines \(lineNumber)-\(endLineNumber)"
    }

    public init(comment: WorkspaceReviewCommentState) {
        self.id = comment.id
        self.path = comment.path
        self.lineNumber = comment.lineNumber
        self.endLineNumber = comment.endLineNumber
        self.lineKind = comment.lineKind
        self.text = comment.text
        self.createdAt = comment.createdAt
    }
}

public struct WorkspaceReviewFileSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var insertions: Int
    public var deletions: Int
    public var hunks: Int
    public var isBinary: Bool
    public var hunkItems: [WorkspaceReviewHunkSurface]
    public var comments: [WorkspaceReviewCommentSurface]

    public var changeLabel: String {
        var parts = ["+\(insertions)", "-\(deletions)"]
        if hunks > 0 {
            parts.append("\(hunks) hunk\(hunks == 1 ? "" : "s")")
        }
        if isBinary {
            parts.append("binary")
        }
        return parts.joined(separator: " · ")
    }

    public var actions: [WorkspaceReviewActionSurface] {
        [
            WorkspaceReviewActionSurface(kind: .stage, path: path),
            WorkspaceReviewActionSurface(kind: .restore, path: path)
        ]
    }

    public init(
        path: String,
        insertions: Int,
        deletions: Int,
        hunks: Int,
        isBinary: Bool = false,
        hunkItems: [WorkspaceReviewHunkSurface] = [],
        comments: [WorkspaceReviewCommentSurface] = []
    ) {
        self.path = path
        self.insertions = insertions
        self.deletions = deletions
        self.hunks = hunks
        self.isBinary = isBinary
        self.hunkItems = hunkItems
        self.comments = comments
    }
}

public enum WorkspaceReviewLineKind: String, Codable, Sendable, Hashable {
    case context
    case insertion
    case deletion

    public var marker: String {
        switch self {
        case .context:
            return " "
        case .insertion:
            return "+"
        case .deletion:
            return "-"
        }
    }
}

public struct WorkspaceReviewLineSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var hunkID: String
    public var oldLineNumber: Int?
    public var newLineNumber: Int?
    public var kind: WorkspaceReviewLineKind
    public var content: String
    public var comments: [WorkspaceReviewCommentSurface]

    public var displayLineNumber: Int? {
        newLineNumber ?? oldLineNumber
    }

    public var lineLabel: String {
        displayLineNumber.map(String.init) ?? ""
    }

    public init(
        id: String,
        path: String,
        hunkID: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        kind: WorkspaceReviewLineKind,
        content: String,
        comments: [WorkspaceReviewCommentSurface] = []
    ) {
        self.id = id
        self.path = path
        self.hunkID = hunkID
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.kind = kind
        self.content = content
        self.comments = comments
    }
}

public struct WorkspaceReviewHunkSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var header: String
    public var insertions: Int
    public var deletions: Int
    public var patch: String
    public var lines: [WorkspaceReviewLineSurface]

    public var changeLabel: String {
        "+\(insertions) · -\(deletions)"
    }

    public var actions: [WorkspaceReviewActionSurface] {
        [
            WorkspaceReviewActionSurface(kind: .stageHunk, path: path, patch: patch, targetID: id),
            WorkspaceReviewActionSurface(kind: .restoreHunk, path: path, patch: patch, targetID: id)
        ]
    }

    public init(
        id: String,
        path: String,
        header: String,
        insertions: Int,
        deletions: Int,
        patch: String,
        lines: [WorkspaceReviewLineSurface] = []
    ) {
        self.id = id
        self.path = path
        self.header = header
        self.insertions = insertions
        self.deletions = deletions
        self.patch = patch
        self.lines = lines
    }
}

public enum WorkspaceReviewActionKind: String, Codable, Sendable, Hashable {
    case stage
    case restore
    case stageHunk = "stage_hunk"
    case restoreHunk = "restore_hunk"

    public var title: String {
        switch self {
        case .stage:
            return "Stage"
        case .restore:
            return "Restore"
        case .stageHunk:
            return "Stage hunk"
        case .restoreHunk:
            return "Restore hunk"
        }
    }

    public var systemImage: String {
        switch self {
        case .stage:
            return "plus.rectangle.on.folder"
        case .restore:
            return "arrow.uturn.backward"
        case .stageHunk:
            return "plus.square.on.square"
        case .restoreHunk:
            return "arrow.uturn.left.square"
        }
    }
}

public struct WorkspaceReviewActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: WorkspaceReviewActionKind
    public var path: String
    public var patch: String?
    public var targetID: String?

    public var id: String {
        "\(kind.rawValue):\(path):\(targetID ?? "file")"
    }

    public init(
        kind: WorkspaceReviewActionKind,
        path: String,
        patch: String? = nil,
        targetID: String? = nil
    ) {
        self.kind = kind
        self.path = path
        self.patch = patch
        self.targetID = targetID
    }
}

public struct MessageSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var accessibilityLabel: String
    public var feedback: MessageFeedbackValue?

    public init(message: ChatMessage, feedback: MessageFeedbackValue? = nil) {
        self.id = message.id
        self.role = message.role
        self.text = message.content
        self.accessibilityLabel = "\(message.role.rawValue): \(message.content)"
        self.feedback = feedback
    }
}

public struct ComposerSurface: Codable, Sendable, Hashable {
    public var draft: String
    public var placeholder: String
    public var isSending: Bool
    public var canSend: Bool
    public var slashSuggestions: [SlashCommandSuggestionSurface]

    public init(composer: ComposerState) {
        self.draft = composer.draft
        self.placeholder = composer.placeholder
        self.isSending = composer.isSending
        self.canSend = !composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !composer.isSending
        self.slashSuggestions = SlashCommandCatalog.suggestions(for: composer.draft)
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
