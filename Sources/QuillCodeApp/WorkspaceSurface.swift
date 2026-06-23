import Foundation
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

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

public struct BrowserSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var addressDraft: String
    public var currentURL: String?
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var canReload: Bool
    public var title: String
    public var statusLabel: String
    public var snapshot: BrowserSnapshotSurface?
    public var comments: [BrowserCommentSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    public var canOpen: Bool {
        !addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        browser: BrowserState,
        emptyTitle: String = "Open a localhost, file, or web page inside QuillCode.",
        emptySubtitle: String = "Use browser comments to keep observations attached to the current page."
    ) {
        self.isVisible = browser.isVisible
        self.addressDraft = browser.addressDraft
        self.currentURL = browser.currentURL
        self.canGoBack = browser.canGoBack
        self.canGoForward = browser.canGoForward
        self.canReload = browser.canReload
        self.title = browser.title
        self.statusLabel = browser.status
        self.snapshot = browser.snapshot.map(BrowserSnapshotSurface.init)
        self.comments = browser.comments.map(BrowserCommentSurface.init)
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
    }
}

public struct BrowserSnapshotSurface: Codable, Sendable, Hashable {
    public var sourceLabel: String
    public var inspectionDepth: BrowserInspectionDepth
    public var summary: String
    public var details: [String]
    public var outline: [String]
    public var textSnippet: String?

    public var inspectionDepthLabel: String {
        inspectionDepth.label
    }

    private enum CodingKeys: String, CodingKey {
        case sourceLabel
        case inspectionDepth
        case summary
        case details
        case outline
        case textSnippet
    }

    public init(snapshot: BrowserSnapshotState) {
        self.sourceLabel = snapshot.sourceLabel
        self.inspectionDepth = snapshot.inspectionDepth
        self.summary = snapshot.summary
        self.details = snapshot.details
        self.outline = snapshot.outline
        self.textSnippet = snapshot.textSnippet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceLabel = try container.decode(String.self, forKey: .sourceLabel)
        self.inspectionDepth = try container.decodeIfPresent(
            BrowserInspectionDepth.self,
            forKey: .inspectionDepth
        ) ?? .metadataOnly
        self.summary = try container.decode(String.self, forKey: .summary)
        self.details = try container.decodeIfPresent([String].self, forKey: .details) ?? []
        self.outline = try container.decodeIfPresent([String].self, forKey: .outline) ?? []
        self.textSnippet = try container.decodeIfPresent(String.self, forKey: .textSnippet)
    }
}

public struct BrowserCommentSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var url: String
    public var text: String

    public init(comment: BrowserCommentState) {
        self.id = comment.id
        self.url = comment.url
        self.text = comment.text
    }
}

public struct WorkspaceExtensionsSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var items: [ProjectExtensionManifestSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    public var pluginCount: Int { items.filter { $0.kind == .plugin }.count }
    public var skillCount: Int { items.filter { $0.kind == .skill }.count }
    public var mcpServerCount: Int { items.filter { $0.kind == .mcpServer }.count }

    public init(
        isVisible: Bool = false,
        manifests: [ProjectExtensionManifest] = [],
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        mcpServerProbeSummaries: [String: MCPServerProbeSummary] = [:],
        emptyTitle: String = "No extension manifests found",
        emptySubtitle: String = "Add JSON manifests under .quillcode/plugins, .quillcode/skills, or .quillcode/mcp."
    ) {
        self.isVisible = isVisible
        self.items = manifests.map {
            ProjectExtensionManifestSurface(
                manifest: $0,
                mcpServerStatus: mcpServerStatuses[$0.id] ?? .stopped,
                probeSummary: mcpServerProbeSummaries[$0.id]
            )
        }
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.title = "Extensions"
        if manifests.isEmpty {
            self.subtitle = "No project-local plugins, skills, or MCP servers discovered"
        } else {
            let pluginCount = manifests.filter { $0.kind == .plugin }.count
            let skillCount = manifests.filter { $0.kind == .skill }.count
            let mcpCount = manifests.filter { $0.kind == .mcpServer }.count
            self.subtitle = [
                Self.countLabel(pluginCount, singular: "plugin"),
                Self.countLabel(skillCount, singular: "skill"),
                Self.countLabel(mcpCount, singular: "MCP server")
            ].joined(separator: " · ")
        }
    }

    private static func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

public struct WorkspaceMemoriesSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var items: [MemoryNoteSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    public var globalCount: Int { items.filter { $0.scope == .global }.count }
    public var projectCount: Int { items.filter { $0.scope == .project }.count }

    public init(
        isVisible: Bool = false,
        notes: [MemoryNote] = [],
        emptyTitle: String = "No memories loaded",
        emptySubtitle: String = "Add Markdown, text, or JSON notes under ~/.quillcode/memories or .quillcode/memories."
    ) {
        self.isVisible = isVisible
        self.items = notes.map(MemoryNoteSurface.init)
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.title = "Memories"
        if notes.isEmpty {
            self.subtitle = "No global or project memories are attached to this thread"
        } else {
            let globalCount = notes.filter { $0.scope == .global }.count
            let projectCount = notes.filter { $0.scope == .project }.count
            self.subtitle = [
                Self.countLabel(globalCount, singular: "global memory"),
                Self.countLabel(projectCount, singular: "project memory")
            ].joined(separator: " · ")
        }
    }

    private static func countLabel(_ count: Int, singular: String) -> String {
        if count == 1 { return "1 \(singular)" }
        if singular.hasSuffix("memory") {
            return "\(count) \(singular.dropLast("memory".count))memories"
        }
        return "\(count) \(singular)s"
    }
}

public struct WorkspaceAutomationsSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var statusLabel: String
    public var emptyTitle: String
    public var emptySubtitle: String
    public var workflows: [AutomationWorkflowSurface]
    public var createThreadFollowUpCommand: WorkspaceCommandSurface?
    public var createWorkspaceScheduleCommand: WorkspaceCommandSurface?
    public var scheduleThreadFollowUpCommands: [WorkspaceCommandSurface]
    public var scheduleWorkspaceScheduleCommands: [WorkspaceCommandSurface]

    public init(
        isVisible: Bool = false,
        automations: [QuillAutomation] = [],
        createThreadFollowUpCommand: WorkspaceCommandSurface? = nil,
        createWorkspaceScheduleCommand: WorkspaceCommandSurface? = nil,
        scheduleThreadFollowUpCommands: [WorkspaceCommandSurface] = [],
        scheduleWorkspaceScheduleCommands: [WorkspaceCommandSurface] = [],
        workflows: [AutomationWorkflowSurface] = AutomationWorkflowSurface.plannedWorkflows,
        emptyTitle: String = "No automations yet",
        emptySubtitle: String = "Create scheduled follow-ups, workspace checks, and monitors once the automation runtime lands."
    ) {
        let sortedAutomations = QuillAutomation.sortedForDisplay(automations)
        let configuredWorkflows = sortedAutomations.map(AutomationWorkflowSurface.init)
        let activeCount = automations.filter { $0.status == .active }.count
        let pausedCount = automations.filter { $0.status == .paused }.count
        self.isVisible = isVisible
        self.title = "Automations"
        self.subtitle = "Recurring work, follow-ups, monitors, and long-running agent jobs"
        self.statusLabel = Self.statusLabel(
            configuredCount: configuredWorkflows.count,
            activeCount: activeCount,
            pausedCount: pausedCount,
            plannedCount: workflows.count
        )
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.workflows = configuredWorkflows.isEmpty ? workflows : configuredWorkflows
        self.createThreadFollowUpCommand = createThreadFollowUpCommand
        self.createWorkspaceScheduleCommand = createWorkspaceScheduleCommand
        self.scheduleThreadFollowUpCommands = scheduleThreadFollowUpCommands
        self.scheduleWorkspaceScheduleCommands = scheduleWorkspaceScheduleCommands
    }

    private static func statusLabel(
        configuredCount: Int,
        activeCount: Int,
        pausedCount: Int,
        plannedCount: Int
    ) -> String {
        guard configuredCount > 0 else { return plannedCount == 0 ? "Empty" : "\(plannedCount) planned" }
        if activeCount > 0, pausedCount > 0 {
            return "\(activeCount) active · \(pausedCount) paused"
        }
        if activeCount > 0 {
            return activeCount == 1 ? "1 active" : "\(activeCount) active"
        }
        return pausedCount == 1 ? "1 paused" : "\(pausedCount) paused"
    }
}

public struct AutomationWorkflowSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var statusLabel: String
    public var scheduleLabel: String
    public var runActionTitle: String?
    public var runCommandID: String?
    public var primaryActionTitle: String?
    public var primaryCommandID: String?
    public var deleteCommandID: String?

    public init(
        id: String,
        title: String,
        detail: String,
        statusLabel: String,
        scheduleLabel: String,
        runActionTitle: String? = nil,
        runCommandID: String? = nil,
        primaryActionTitle: String? = nil,
        primaryCommandID: String? = nil,
        deleteCommandID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.statusLabel = statusLabel
        self.scheduleLabel = scheduleLabel
        self.runActionTitle = runActionTitle
        self.runCommandID = runCommandID
        self.primaryActionTitle = primaryActionTitle
        self.primaryCommandID = primaryCommandID
        self.deleteCommandID = deleteCommandID
    }

    public init(automation: QuillAutomation) {
        let uuid = automation.id.uuidString
        self.id = automation.id.uuidString
        self.title = automation.title
        self.detail = automation.detail
        self.statusLabel = Self.statusLabel(for: automation)
        self.scheduleLabel = automation.scheduleDescription.isEmpty
            ? automation.scheduleKind.label
            : automation.scheduleDescription
        self.runActionTitle = automation.status == .active && automation.kind != .monitor
            ? "Run now"
            : nil
        self.runCommandID = automation.status == .active && automation.kind != .monitor
            ? "automation-run:\(uuid)"
            : nil
        self.primaryActionTitle = automation.status == .active ? "Pause" : "Resume"
        self.primaryCommandID = automation.status == .active
            ? "automation-pause:\(uuid)"
            : "automation-resume:\(uuid)"
        self.deleteCommandID = "automation-delete:\(uuid)"
    }

    private static func statusLabel(for automation: QuillAutomation) -> String {
        guard automation.status == .active else { return automation.status.label }
        if let nextRunAt = automation.nextRunAt, nextRunAt <= Date() {
            return "Due"
        }
        if automation.lastRunAt != nil, automation.nextRunAt == nil {
            return "Ran"
        }
        return automation.status.label
    }

    public static let plannedWorkflows: [AutomationWorkflowSurface] = [
        AutomationWorkflowSurface(
            id: "thread-followups",
            title: "Thread follow-ups",
            detail: "Wake a conversation later with the same project, model, and context.",
            statusLabel: "Planned",
            scheduleLabel: "Heartbeat"
        ),
        AutomationWorkflowSurface(
            id: "workspace-schedules",
            title: "Workspace schedules",
            detail: "Run repeatable repo checks, local environment actions, or reports.",
            statusLabel: "Planned",
            scheduleLabel: "Cron"
        ),
        AutomationWorkflowSurface(
            id: "monitors",
            title: "Monitors",
            detail: "Watch CI, PRs, endpoints, or files and surface actionable changes.",
            statusLabel: "Planned",
            scheduleLabel: "Event"
        )
    ]
}

public struct MemoryNoteSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var scope: MemoryScope
    public var scopeLabel: String
    public var title: String
    public var preview: String
    public var relativePath: String
    public var byteCountLabel: String
    public var canDelete: Bool
    public var deleteCommandID: String?

    public init(note: MemoryNote) {
        self.id = note.id
        self.scope = note.scope
        self.scopeLabel = note.scope.title
        self.title = note.title
        self.preview = Self.preview(note.content, wasTruncated: note.wasTruncated)
        self.relativePath = note.relativePath
        self.byteCountLabel = note.wasTruncated
            ? "\(note.byteCount) bytes, truncated"
            : "\(note.byteCount) bytes"
        self.canDelete = note.scope == .global
        self.deleteCommandID = note.scope == .global ? "memory-delete:\(note.id)" : nil
    }

    private static func preview(_ content: String, wasTruncated: Bool) -> String {
        let normalized = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > 180 else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: 180)
        return "\(normalized[..<end])..."
    }
}

public struct ProjectExtensionManifestSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ProjectExtensionKind
    public var kindLabel: String
    public var name: String
    public var summary: String
    public var versionLabel: String?
    public var sourceURL: String?
    public var relativePath: String
    public var statusLabel: String
    public var transportLabel: String?
    public var launchCommand: String?
    public var updateCommand: String?
    public var serverLabel: String?
    public var protocolLabel: String?
    public var toolCountLabel: String?
    public var toolDescriptors: [MCPToolDescriptor]
    public var toolNames: [String]
    public var resourceCountLabel: String?
    public var resourceNames: [String]
    public var promptCountLabel: String?
    public var promptNames: [String]
    public var probeError: String?
    public var canStart: Bool
    public var canStop: Bool
    public var canUpdate: Bool
    public var startCommandID: String?
    public var stopCommandID: String?
    public var updateCommandID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case kindLabel
        case name
        case summary
        case versionLabel
        case sourceURL
        case relativePath
        case statusLabel
        case transportLabel
        case launchCommand
        case updateCommand
        case serverLabel
        case protocolLabel
        case toolCountLabel
        case toolDescriptors
        case toolNames
        case resourceCountLabel
        case resourceNames
        case promptCountLabel
        case promptNames
        case probeError
        case canStart
        case canStop
        case canUpdate
        case startCommandID
        case stopCommandID
        case updateCommandID
    }

    public init(
        manifest: ProjectExtensionManifest,
        mcpServerStatus: MCPServerLifecycleStatus = .stopped,
        probeSummary: MCPServerProbeSummary? = nil
    ) {
        self.id = manifest.id
        self.kind = manifest.kind
        self.kindLabel = manifest.kind.title
        self.name = manifest.name
        self.summary = manifest.summary
        self.versionLabel = manifest.version.map { "v\($0)" }
        self.sourceURL = manifest.sourceURL
        self.relativePath = manifest.relativePath
        if manifest.isEnabled {
            if manifest.kind == .mcpServer {
                self.statusLabel = manifest.launchExecutable == nil ? "Missing command" : mcpServerStatus.title
            } else {
                self.statusLabel = "Discovered"
            }
        } else {
            self.statusLabel = "Disabled"
        }
        self.transportLabel = manifest.transport?.rawValue.uppercased()
        self.launchCommand = manifest.launchCommand
        self.updateCommand = manifest.updateCommand
        self.serverLabel = probeSummary?.serverLabel
        self.protocolLabel = probeSummary?.protocolVersion.map { "MCP \($0)" }
        self.toolCountLabel = probeSummary?.toolCountLabel
        let descriptors = Array((probeSummary?.toolDescriptors ?? []).prefix(4))
        self.toolDescriptors = descriptors
        self.toolNames = descriptors.isEmpty
            ? Array((probeSummary?.toolNames ?? []).prefix(4))
            : descriptors.map(\.name)
        self.resourceCountLabel = probeSummary?.resourceCountLabel
        self.resourceNames = Array((probeSummary?.resourceNames ?? []).prefix(4))
        self.promptCountLabel = probeSummary?.promptCountLabel
        self.promptNames = Array((probeSummary?.promptNames ?? []).prefix(4))
        self.probeError = probeSummary?.errorMessage
        self.canStart = manifest.kind == .mcpServer
            && manifest.isEnabled
            && manifest.launchExecutable != nil
            && !mcpServerStatus.isActive
        self.canStop = manifest.kind == .mcpServer && mcpServerStatus.isActive
        self.canUpdate = manifest.updateCommand != nil
        self.startCommandID = canStart ? "mcp-start:\(manifest.id)" : nil
        self.stopCommandID = canStop ? "mcp-stop:\(manifest.id)" : nil
        self.updateCommandID = canUpdate ? "extension-update:\(manifest.id)" : nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = try container.decode(ProjectExtensionKind.self, forKey: .kind)
        self.kindLabel = try container.decode(String.self, forKey: .kindLabel)
        self.name = try container.decode(String.self, forKey: .name)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.versionLabel = try container.decodeIfPresent(String.self, forKey: .versionLabel)
        self.sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        self.relativePath = try container.decode(String.self, forKey: .relativePath)
        self.statusLabel = try container.decode(String.self, forKey: .statusLabel)
        self.transportLabel = try container.decodeIfPresent(String.self, forKey: .transportLabel)
        self.launchCommand = try container.decodeIfPresent(String.self, forKey: .launchCommand)
        self.updateCommand = try container.decodeIfPresent(String.self, forKey: .updateCommand)
        self.serverLabel = try container.decodeIfPresent(String.self, forKey: .serverLabel)
        self.protocolLabel = try container.decodeIfPresent(String.self, forKey: .protocolLabel)
        self.toolCountLabel = try container.decodeIfPresent(String.self, forKey: .toolCountLabel)
        self.toolDescriptors = try container.decodeIfPresent([MCPToolDescriptor].self, forKey: .toolDescriptors) ?? []
        self.toolNames = try container.decodeIfPresent([String].self, forKey: .toolNames) ?? []
        if self.toolDescriptors.isEmpty {
            self.toolDescriptors = self.toolNames.map { MCPToolDescriptor(name: $0) }
        }
        if self.toolNames.isEmpty {
            self.toolNames = self.toolDescriptors.map(\.name)
        }
        self.resourceCountLabel = try container.decodeIfPresent(String.self, forKey: .resourceCountLabel)
        self.resourceNames = try container.decodeIfPresent([String].self, forKey: .resourceNames) ?? []
        self.promptCountLabel = try container.decodeIfPresent(String.self, forKey: .promptCountLabel)
        self.promptNames = try container.decodeIfPresent([String].self, forKey: .promptNames) ?? []
        self.probeError = try container.decodeIfPresent(String.self, forKey: .probeError)
        self.canStart = try container.decode(Bool.self, forKey: .canStart)
        self.canStop = try container.decode(Bool.self, forKey: .canStop)
        self.canUpdate = try container.decodeIfPresent(Bool.self, forKey: .canUpdate) ?? false
        self.startCommandID = try container.decodeIfPresent(String.self, forKey: .startCommandID)
        self.stopCommandID = try container.decodeIfPresent(String.self, forKey: .stopCommandID)
        self.updateCommandID = try container.decodeIfPresent(String.self, forKey: .updateCommandID)
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

public struct WorkspaceCommandSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var shortcut: String?
    public var category: String
    public var keywords: [String]
    public var isEnabled: Bool

    public init(
        id: String,
        title: String,
        shortcut: String? = nil,
        category: String = WorkspaceCommandPalette.workspaceCategory,
        keywords: [String] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.category = category
        self.keywords = keywords
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case shortcut
        case category
        case keywords
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut)
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
            ?? WorkspaceCommandPalette.workspaceCategory
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(shortcut, forKey: .shortcut)
        try container.encode(category, forKey: .category)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

public enum TopBarOverflowCommandCatalog {
    public static func commandIDs(showsComputerUseSetup: Bool) -> [String] {
        var commandIDs = [
            "command-palette",
            "search"
        ]
        if showsComputerUseSetup {
            commandIDs.append("computer-use-setup")
        }
        commandIDs.append(contentsOf: [
            "settings",
            "keyboard-shortcuts",
            "stop-all"
        ])
        return commandIDs
    }

    public static func commands(
        from commands: [WorkspaceCommandSurface],
        showsComputerUseSetup: Bool
    ) -> [WorkspaceCommandSurface] {
        commandIDs(showsComputerUseSetup: showsComputerUseSetup).compactMap { commandID in
            commands.first { $0.id == commandID }
        }
    }

    public static func testID(for commandID: String) -> String {
        switch commandID {
        case "computer-use-setup":
            return "top-bar-overflow-computer-use"
        default:
            return "top-bar-overflow-\(commandID)"
        }
    }
}

public extension WorkspaceCommandSurface {
    static func automationCreateThreadFollowUp(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "automation-create-thread-follow-up",
            title: "Create thread follow-up",
            category: WorkspaceCommandPalette.automationsCategory,
            keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule"],
            isEnabled: isEnabled
        )
    }

    static func automationCreateWorkspaceSchedule(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "automation-create-workspace-schedule",
            title: "Create workspace schedule",
            category: WorkspaceCommandPalette.automationsCategory,
            keywords: ["automation", "workspace", "schedule", "repo", "check", "cron"],
            isEnabled: isEnabled
        )
    }

    static func automationScheduleThreadFollowUpCommands(isEnabled: Bool) -> [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "automation-create-thread-follow-up-after:600",
                title: "In 10 minutes",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule", "ten minutes"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-thread-follow-up-after:3600",
                title: "In 1 hour",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule", "hour"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-thread-follow-up-tomorrow",
                title: "Tomorrow morning",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule", "tomorrow", "morning"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-thread-follow-up-every:daily",
                title: "Daily follow-up",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule", "daily", "recurring"],
                isEnabled: isEnabled
            )
        ]
    }

    static func automationScheduleWorkspaceScheduleCommands(isEnabled: Bool) -> [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "automation-create-workspace-schedule-after:600",
                title: "Check in 10 minutes",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "workspace", "schedule", "repo", "check", "ten minutes"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-workspace-schedule-after:3600",
                title: "Check in 1 hour",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "workspace", "schedule", "repo", "check", "hour"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-workspace-schedule-tomorrow",
                title: "Check tomorrow morning",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "workspace", "schedule", "repo", "check", "tomorrow", "morning"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-workspace-schedule-every:daily",
                title: "Check daily",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "workspace", "schedule", "repo", "check", "daily", "recurring", "cron"],
                isEnabled: isEnabled
            )
        ]
    }

    static func computerUseSetup(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "computer-use-setup",
            title: "Computer Use setup",
            category: WorkspaceCommandPalette.computerUseCategory,
            keywords: ["screen", "accessibility", "permissions"],
            isEnabled: isEnabled
        )
    }

    static func computerUseScreenRecordingSettings(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "computer-use-open-screen-recording",
            title: "Open Screen Recording settings",
            category: WorkspaceCommandPalette.computerUseCategory,
            keywords: ["screen", "recording", "capture", "permissions"],
            isEnabled: isEnabled
        )
    }

    static func computerUseAccessibilitySettings(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "computer-use-open-accessibility",
            title: "Open Accessibility settings",
            category: WorkspaceCommandPalette.computerUseCategory,
            keywords: ["accessibility", "click", "keyboard", "permissions"],
            isEnabled: isEnabled
        )
    }

    static let computerUseRefresh = WorkspaceCommandSurface(
        id: "computer-use-refresh",
        title: "Refresh Computer Use status",
        category: WorkspaceCommandPalette.computerUseCategory,
        keywords: ["computer use", "permissions", "refresh", "status"]
    )
}

public struct WorkspaceCommandGroupSurface: Sendable, Hashable, Identifiable {
    public var id: String { title }
    public var title: String
    public var commands: [WorkspaceCommandSurface]
}

public enum WorkspaceCommandPalette {
    public static let threadCategory = "Thread"
    public static let navigationCategory = "Navigation"
    public static let workspaceCategory = "Workspace"
    public static let slashCategory = "Slash Commands"
    public static let gitCategory = "Git"
    public static let environmentCategory = "Environment"
    public static let controlCategory = "Control"
    public static let computerUseCategory = "Computer Use"
    public static let automationsCategory = "Automations"
    public static let extensionsCategory = "Extensions"
    public static let memoriesCategory = "Memories"

    public static let categoryOrder = [
        threadCategory,
        navigationCategory,
        workspaceCategory,
        automationsCategory,
        memoriesCategory,
        extensionsCategory,
        gitCategory,
        slashCategory,
        environmentCategory,
        controlCategory,
        computerUseCategory
    ]

    public static func rankedCommands(
        _ commands: [WorkspaceCommandSurface],
        matching query: String
    ) -> [WorkspaceCommandSurface] {
        let request = QueryRequest(query)
        let searchableCommands = request.searchableCommands(from: commands)
        let scoredCommands = searchableCommands.enumerated().compactMap { index, command in
            score(command, query: request.normalizedQuery).map { score in
                (index: index, command: command, score: score)
            }
        }
        return scoredCommands.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsCategory = categoryRank(lhs.command.category)
            let rhsCategory = categoryRank(rhs.command.category)
            if lhsCategory != rhsCategory {
                return lhsCategory < rhsCategory
            }
            return lhs.index < rhs.index
        }
        .map(\.command)
    }

    public static func groupedCommands(
        _ commands: [WorkspaceCommandSurface],
        matching query: String
    ) -> [WorkspaceCommandGroupSurface] {
        var groupsByCategory: [String: [WorkspaceCommandSurface]] = [:]
        for command in rankedCommands(commands, matching: query) {
            groupsByCategory[command.category, default: []].append(command)
        }
        return groupsByCategory.keys.sorted { lhs, rhs in
            let lhsRank = categoryRank(lhs)
            let rhsRank = categoryRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs < rhs
        }
        .map { category in
            WorkspaceCommandGroupSurface(title: category, commands: groupsByCategory[category] ?? [])
        }
    }

    private static func score(_ command: WorkspaceCommandSurface, query: String) -> Int? {
        guard !query.isEmpty else {
            return 1
        }

        let title = normalize(command.title)
        let compactTitle = compact(title)
        let shortcut = compact(normalize(command.shortcut ?? ""))
        let id = normalize(command.id.replacingOccurrences(of: "-", with: " "))
        let category = normalize(command.category)
        let keywords = command.keywords.map(normalize)
        let compactQuery = compact(query)

        if title == query || compactTitle == compactQuery {
            return 1_000
        }
        if title.hasPrefix(query) || compactTitle.hasPrefix(compactQuery) {
            return 900
        }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(query) }) {
            return 820
        }
        if !shortcut.isEmpty && shortcut.contains(compactQuery) {
            return 780
        }
        if keywords.contains(where: { $0 == query || $0.hasPrefix(query) }) {
            return 720
        }
        if title.contains(query) || compactTitle.contains(compactQuery) {
            return 650
        }
        if id.contains(query) || keywords.contains(where: { $0.contains(query) }) {
            return 560
        }
        let tokens = queryTokens(query)
        if tokens.count > 1 {
            let searchableTokens = commandTokens(title: title, id: id, category: category, keywords: keywords)
            if tokens.allSatisfy({ token in searchableTokens.contains(where: { $0.hasPrefix(token) }) }) {
                return 520
            }
        }
        if category.contains(query) {
            return 440
        }
        return nil
    }

    private static func queryTokens(_ query: String) -> [Substring] {
        query.split(whereSeparator: \.isWhitespace)
    }

    private static func commandTokens(
        title: String,
        id: String,
        category: String,
        keywords: [String]
    ) -> [Substring] {
        ([title, id, category] + keywords)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
    }

    private struct QueryRequest {
        enum Scope {
            case mixed
            case actions
            case slash
        }

        var scope: Scope
        var normalizedQuery: String

        init(_ rawQuery: String) {
            let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(">") {
                self.scope = .actions
                self.normalizedQuery = WorkspaceCommandPalette.normalize(String(trimmed.dropFirst()))
            } else if trimmed.hasPrefix("/") {
                self.scope = .slash
                self.normalizedQuery = WorkspaceCommandPalette.normalize(String(trimmed.dropFirst()))
            } else {
                self.scope = .mixed
                self.normalizedQuery = WorkspaceCommandPalette.normalize(trimmed)
            }
        }

        func searchableCommands(from commands: [WorkspaceCommandSurface]) -> [WorkspaceCommandSurface] {
            switch scope {
            case .actions:
                return commands
            case .slash:
                return SlashCommandCatalog.commandPaletteCommands()
            case .mixed:
                guard !normalizedQuery.isEmpty else { return commands }
                return commands + SlashCommandCatalog.commandPaletteCommands()
            }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func compact(_ value: String) -> String {
        value.filter { !$0.isWhitespace && $0 != "+" }
    }

    private static func categoryRank(_ category: String) -> Int {
        categoryOrder.firstIndex(of: category) ?? categoryOrder.count
    }
}

public struct ComputerUseRequirementSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var statusLabel: String
    public var isGranted: Bool
    public var command: WorkspaceCommandSurface

    public init(
        id: String,
        title: String,
        detail: String,
        statusLabel: String,
        isGranted: Bool,
        command: WorkspaceCommandSurface
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.statusLabel = statusLabel
        self.isGranted = isGranted
        self.command = command
    }
}

public struct WorkspaceSettingsSurface: Codable, Sendable, Hashable {
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var hasStoredAPIKey: Bool
    public var signInURL: String
    public var apiKeyStatusLabel: String
    public var loginStatusLabel: String
    public var accountLabel: String?
    public var runtimeIssue: RuntimeIssueSurface?
    public var computerUseStatus: ComputerUseStatus
    public var computerUseSetupCommand: WorkspaceCommandSurface
    public var computerUseScreenRecordingCommand: WorkspaceCommandSurface
    public var computerUseAccessibilityCommand: WorkspaceCommandSurface
    public var computerUseRefreshCommand: WorkspaceCommandSurface
    public var computerUseStatusLabel: String
    public var computerUseSetupSummary: String
    public var computerUseNextAction: String
    public var computerUseRequirements: [ComputerUseRequirementSurface]

    public init(
        config: AppConfig,
        hasStoredAPIKey: Bool,
        runtimeIssue: RuntimeIssueSurface? = nil,
        computerUseStatus: ComputerUseStatus = .permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        )
    ) {
        self.apiBaseURL = config.apiBaseURL
        self.authMode = config.authMode
        self.developerOverrideEnabled = config.developerOverrideEnabled
        self.hasStoredAPIKey = hasStoredAPIKey
        self.signInURL = TrustedRouterDefaults.loopbackCallbackURL
        self.accountLabel = config.trustedRouterAccount?.displayLabel
        self.runtimeIssue = runtimeIssue
        self.computerUseStatus = computerUseStatus
        self.computerUseSetupCommand = WorkspaceCommandSurface.computerUseSetup(isEnabled: !computerUseStatus.available)
        self.computerUseScreenRecordingCommand = WorkspaceCommandSurface.computerUseScreenRecordingSettings(isEnabled: !computerUseStatus.screenRecordingGranted)
        self.computerUseAccessibilityCommand = WorkspaceCommandSurface.computerUseAccessibilitySettings(isEnabled: !computerUseStatus.accessibilityGranted)
        self.computerUseRefreshCommand = WorkspaceCommandSurface.computerUseRefresh
        self.computerUseStatusLabel = Self.computerUseStatusLabel(computerUseStatus)
        self.computerUseSetupSummary = Self.computerUseSetupSummary(computerUseStatus)
        self.computerUseNextAction = Self.computerUseNextAction(computerUseStatus)
        self.computerUseRequirements = Self.computerUseRequirements(
            status: computerUseStatus,
            screenRecordingCommand: computerUseScreenRecordingCommand,
            accessibilityCommand: computerUseAccessibilityCommand
        )
        switch config.authMode {
        case .oauth:
            self.apiKeyStatusLabel = hasStoredAPIKey ? "Signed in" : "Not signed in"
            if hasStoredAPIKey, let accountLabel {
                self.loginStatusLabel = "Signed in as \(accountLabel)"
            } else {
                self.loginStatusLabel = hasStoredAPIKey ? "TrustedRouter OAuth ready" : "TrustedRouter login required"
            }
        case .developerOverride:
            self.apiKeyStatusLabel = hasStoredAPIKey ? "API key configured" : "No API key saved"
            self.loginStatusLabel = hasStoredAPIKey ? "TrustedRouter developer override ready" : "Developer override needs an API key"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case apiBaseURL
        case authMode
        case developerOverrideEnabled
        case hasStoredAPIKey
        case signInURL
        case apiKeyStatusLabel
        case loginStatusLabel
        case accountLabel
        case runtimeIssue
        case computerUseStatus
        case computerUseSetupCommand
        case computerUseScreenRecordingCommand
        case computerUseAccessibilityCommand
        case computerUseRefreshCommand
        case computerUseStatusLabel
        case computerUseSetupSummary
        case computerUseNextAction
        case computerUseRequirements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.apiBaseURL = try container.decode(String.self, forKey: .apiBaseURL)
        self.authMode = try container.decode(TrustedRouterAuthMode.self, forKey: .authMode)
        self.developerOverrideEnabled = try container.decode(Bool.self, forKey: .developerOverrideEnabled)
        self.hasStoredAPIKey = try container.decode(Bool.self, forKey: .hasStoredAPIKey)
        self.signInURL = try container.decode(String.self, forKey: .signInURL)
        self.apiKeyStatusLabel = try container.decode(String.self, forKey: .apiKeyStatusLabel)
        self.loginStatusLabel = try container.decode(String.self, forKey: .loginStatusLabel)
        self.accountLabel = try container.decodeIfPresent(String.self, forKey: .accountLabel)
        self.runtimeIssue = try container.decodeIfPresent(RuntimeIssueSurface.self, forKey: .runtimeIssue)
        let decodedComputerUseStatus = try container.decodeIfPresent(ComputerUseStatus.self, forKey: .computerUseStatus)
            ?? .permissionStatus(screenRecordingGranted: false, accessibilityGranted: false)
        self.computerUseStatus = decodedComputerUseStatus
        self.computerUseSetupCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseSetupCommand
        ) ?? .computerUseSetup(isEnabled: !decodedComputerUseStatus.available)
        self.computerUseScreenRecordingCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseScreenRecordingCommand
        ) ?? .computerUseScreenRecordingSettings(isEnabled: !decodedComputerUseStatus.screenRecordingGranted)
        self.computerUseAccessibilityCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseAccessibilityCommand
        ) ?? .computerUseAccessibilitySettings(isEnabled: !decodedComputerUseStatus.accessibilityGranted)
        self.computerUseRefreshCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseRefreshCommand
        ) ?? .computerUseRefresh
        self.computerUseStatusLabel = try container.decodeIfPresent(String.self, forKey: .computerUseStatusLabel)
            ?? Self.computerUseStatusLabel(decodedComputerUseStatus)
        self.computerUseSetupSummary = try container.decodeIfPresent(String.self, forKey: .computerUseSetupSummary)
            ?? Self.computerUseSetupSummary(decodedComputerUseStatus)
        self.computerUseNextAction = try container.decodeIfPresent(String.self, forKey: .computerUseNextAction)
            ?? Self.computerUseNextAction(decodedComputerUseStatus)
        self.computerUseRequirements = try container.decodeIfPresent(
            [ComputerUseRequirementSurface].self,
            forKey: .computerUseRequirements
        ) ?? Self.computerUseRequirements(
            status: decodedComputerUseStatus,
            screenRecordingCommand: computerUseScreenRecordingCommand,
            accessibilityCommand: computerUseAccessibilityCommand
        )
    }

    private static func computerUseStatusLabel(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Ready"
        }
        if !status.screenRecordingGranted && !status.accessibilityGranted {
            return "Setup needed"
        }
        if !status.screenRecordingGranted {
            return "Screen Recording needed"
        }
        return "Accessibility needed"
    }

    private static func computerUseSetupSummary(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Ready for screenshots, clicks, typing, scrolling, and keyboard shortcuts."
        }
        return "Computer Use needs macOS privacy permissions before QuillCode can inspect or control the desktop."
    }

    private static func computerUseNextAction(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Computer Use is enabled. Ask QuillCode to inspect the screen or operate an app."
        }
        if !status.screenRecordingGranted && !status.accessibilityGranted {
            return "Open Screen Recording first, enable QuillCode, then open Accessibility."
        }
        if !status.screenRecordingGranted {
            return "Open Screen Recording, enable QuillCode, then refresh status."
        }
        return "Open Accessibility, enable QuillCode, then refresh status."
    }

    private static func computerUseRequirements(
        status: ComputerUseStatus,
        screenRecordingCommand: WorkspaceCommandSurface,
        accessibilityCommand: WorkspaceCommandSurface
    ) -> [ComputerUseRequirementSurface] {
        [
            ComputerUseRequirementSurface(
                id: "screen-recording",
                title: "Screen Recording",
                detail: "Required for screenshots and visual inspection.",
                statusLabel: status.screenRecordingGranted ? "Granted" : "Required",
                isGranted: status.screenRecordingGranted,
                command: screenRecordingCommand
            ),
            ComputerUseRequirementSurface(
                id: "accessibility",
                title: "Accessibility",
                detail: "Required for clicks, typing, scrolling, cursor moves, and keyboard shortcuts.",
                statusLabel: status.accessibilityGranted ? "Granted" : "Required",
                isGranted: status.accessibilityGranted,
                command: accessibilityCommand
            )
        ]
    }
}

public struct WorkspaceSettingsUpdate: Sendable, Hashable {
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var replacementAPIKey: String?
    public var shouldClearAPIKey: Bool

    public init(
        apiBaseURL: String,
        authMode: TrustedRouterAuthMode = .oauth,
        developerOverrideEnabled: Bool,
        replacementAPIKey: String? = nil,
        shouldClearAPIKey: Bool = false
    ) {
        self.apiBaseURL = apiBaseURL
        self.authMode = developerOverrideEnabled ? .developerOverride : authMode
        self.developerOverrideEnabled = developerOverrideEnabled || authMode == .developerOverride
        self.replacementAPIKey = replacementAPIKey
        self.shouldClearAPIKey = shouldClearAPIKey
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
                messages: thread.map(Self.messageSurfaces(for:)) ?? [],
                toolCards: toolCards,
                timelineItems: thread == nil ? nil : currentTimelineItems
            ),
            contextBanner: contextBanner(for: thread),
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

    private func contextBanner(for thread: ChatThread?) -> ContextBannerSurface? {
        guard let thread, !thread.messages.isEmpty else { return nil }
        let usedPercent = Self.contextUsedPercent(for: thread)
        guard usedPercent >= Self.contextWarningThresholdPercent else { return nil }
        let isFull = usedPercent >= 100
        return ContextBannerSurface(
            usedPercent: usedPercent,
            title: "\(isFull ? "Context limit reached" : "Approaching context limit") (\(usedPercent)% used)",
            subtitle: "Older turns may drop out soon. Compact the thread, start fresh, or fork from the latest useful context.",
            newThreadCommand: WorkspaceCommandSurface(id: "new-chat", title: "New thread"),
            forkCommand: WorkspaceCommandSurface(id: "fork-from-last", title: "Fork from last"),
            compactCommand: WorkspaceCommandSurface(id: "compact-context", title: "Compact context")
        )
    }

    private static let contextTokenBudget = 32_000
    private static let contextWarningThresholdPercent = 80

    private static func contextUsedPercent(for thread: ChatThread) -> Int {
        let estimatedTokens = max(1, estimatedContextTokens(for: thread))
        return min(100, Int((Double(estimatedTokens) / Double(contextTokenBudget) * 100).rounded()))
    }

    private static func estimatedContextTokens(for thread: ChatThread) -> Int {
        let messageCharacters = thread.messages.reduce(0) { total, message in
            total + message.content.count + 24
        }
        let eventCharacters = thread.events.reduce(0) { total, event in
            total + event.summary.count + (event.payloadJSON?.count ?? 0)
        }
        let instructionCharacters = thread.instructions.reduce(0) { total, instruction in
            total + instruction.content.count
        }
        return (messageCharacters + eventCharacters + instructionCharacters) / 4
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
