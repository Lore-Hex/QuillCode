import Foundation
import QuillCodeCore

public struct WorkspaceSurface: Codable, Sendable, Hashable {
    public var topBar: TopBarSurface
    public var projects: ProjectListSurface
    public var sidebar: SidebarSurface
    public var transcript: TranscriptSurface
    public var review: WorkspaceReviewSurface
    public var terminal: TerminalSurface
    public var composer: ComposerSurface
    public var commands: [WorkspaceCommandSurface]
    public var settings: WorkspaceSettingsSurface
    public var lastError: String?

    public init(
        topBar: TopBarSurface,
        projects: ProjectListSurface,
        sidebar: SidebarSurface,
        transcript: TranscriptSurface,
        review: WorkspaceReviewSurface,
        terminal: TerminalSurface,
        composer: ComposerSurface,
        commands: [WorkspaceCommandSurface],
        settings: WorkspaceSettingsSurface,
        lastError: String? = nil
    ) {
        self.topBar = topBar
        self.projects = projects
        self.sidebar = sidebar
        self.transcript = transcript
        self.review = review
        self.terminal = terminal
        self.composer = composer
        self.commands = commands
        self.settings = settings
        self.lastError = lastError
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
    public var isSelected: Bool

    public init(project: ProjectRef, selectedProjectID: UUID?) {
        self.id = project.id
        self.name = project.name
        self.path = project.path
        self.isSelected = project.id == selectedProjectID
    }
}

public struct TopBarSurface: Codable, Sendable, Hashable {
    public var appName: String
    public var primaryTitle: String
    public var subtitle: String
    public var modelLabel: String
    public var selectedModelID: String
    public var modelCategories: [ModelCategorySurface]
    public var modeLabel: String
    public var agentStatus: String
    public var computerUseLabel: String
    public var showsComputerUseSetup: Bool

    public init(
        appName: String,
        primaryTitle: String,
        subtitle: String,
        modelLabel: String,
        selectedModelID: String,
        modelCategories: [ModelCategorySurface],
        modeLabel: String,
        agentStatus: String,
        computerUseLabel: String,
        showsComputerUseSetup: Bool
    ) {
        self.appName = appName
        self.primaryTitle = primaryTitle
        self.subtitle = subtitle
        self.modelLabel = modelLabel
        self.selectedModelID = selectedModelID
        self.modelCategories = modelCategories
        self.modeLabel = modeLabel
        self.agentStatus = agentStatus
        self.computerUseLabel = computerUseLabel
        self.showsComputerUseSetup = showsComputerUseSetup
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

public struct ModelOptionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: String
    public var displayName: String
    public var category: String
    public var isSelected: Bool

    public init(model: ModelInfo, selectedModelID: String) {
        self.id = model.id
        self.provider = model.provider
        self.displayName = model.displayName
        self.category = model.category
        self.isSelected = model.id == selectedModelID
    }
}

public struct SidebarSurface: Codable, Sendable, Hashable {
    public var title: String
    public var items: [SidebarItemSurface]
    public var selectedThreadID: UUID?
    public var emptyTitle: String

    public init(
        title: String = "Chats",
        items: [SidebarItemSurface],
        selectedThreadID: UUID?,
        emptyTitle: String = "No chats yet"
    ) {
        self.title = title
        self.items = items
        self.selectedThreadID = selectedThreadID
        self.emptyTitle = emptyTitle
    }

    public func filteredItems(matching query: String) -> [SidebarItemSurface] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return items
        }
        return items.filter { item in
            let pinLabel = item.isPinned ? "pinned" : ""
            return item.title.localizedCaseInsensitiveContains(normalizedQuery)
                || item.subtitle.localizedCaseInsensitiveContains(normalizedQuery)
                || pinLabel.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

public struct SidebarItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var isSelected: Bool
    public var isPinned: Bool

    public init(item: SidebarItem, selectedThreadID: UUID?) {
        self.id = item.id
        self.title = item.title
        self.subtitle = item.subtitle
        self.isSelected = item.id == selectedThreadID
        self.isPinned = item.isPinned
    }
}

public struct TranscriptSurface: Codable, Sendable, Hashable {
    public var messages: [MessageSurface]
    public var toolCards: [ToolCardState]
    public var emptyTitle: String
    public var emptySubtitle: String

    public init(
        messages: [MessageSurface],
        toolCards: [ToolCardState],
        emptyTitle: String = "Ask QuillCode to inspect, edit, or run this project.",
        emptySubtitle: String = "Use Auto for normal coding work, Review for manual gates, or Read-only for exploration."
    ) {
        self.messages = messages
        self.toolCards = toolCards
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
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

    public init(
        terminal: TerminalState,
        cwd: URL?,
        emptyTitle: String = "Run commands in this project without leaving QuillCode."
    ) {
        self.isVisible = terminal.isVisible
        self.draft = terminal.draft
        self.isRunning = terminal.isRunning
        self.cwdLabel = cwd?.path ?? "No project"
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
    public var isSuccess: Bool

    public init(entry: TerminalCommandState) {
        self.id = entry.id
        self.command = entry.command
        self.stdout = entry.stdout
        self.stderr = entry.stderr
        self.exitCodeLabel = entry.exitCode.map { "exit \($0)" } ?? "exit unknown"
        self.statusLabel = entry.ok ? "Done" : "Failed"
        self.isSuccess = entry.ok
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
        hunkItems: [WorkspaceReviewHunkSurface] = []
    ) {
        self.path = path
        self.insertions = insertions
        self.deletions = deletions
        self.hunks = hunks
        self.isBinary = isBinary
        self.hunkItems = hunkItems
    }
}

public struct WorkspaceReviewHunkSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var header: String
    public var insertions: Int
    public var deletions: Int
    public var patch: String

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
        patch: String
    ) {
        self.id = id
        self.path = path
        self.header = header
        self.insertions = insertions
        self.deletions = deletions
        self.patch = patch
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

    public init(message: ChatMessage) {
        self.id = message.id
        self.role = message.role
        self.text = message.content
        self.accessibilityLabel = "\(message.role.rawValue): \(message.content)"
    }
}

public struct ComposerSurface: Codable, Sendable, Hashable {
    public var draft: String
    public var placeholder: String
    public var isSending: Bool
    public var canSend: Bool

    public init(composer: ComposerState) {
        self.draft = composer.draft
        self.placeholder = composer.placeholder
        self.isSending = composer.isSending
        self.canSend = !composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !composer.isSending
    }
}

public struct WorkspaceCommandSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var shortcut: String?
    public var isEnabled: Bool

    public init(id: String, title: String, shortcut: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
    }
}

public struct WorkspaceSettingsSurface: Codable, Sendable, Hashable {
    public var apiBaseURL: String
    public var developerOverrideEnabled: Bool
    public var hasStoredAPIKey: Bool
    public var apiKeyStatusLabel: String
    public var loginStatusLabel: String

    public init(config: AppConfig, hasStoredAPIKey: Bool) {
        self.apiBaseURL = config.apiBaseURL
        self.developerOverrideEnabled = config.developerOverrideEnabled
        self.hasStoredAPIKey = hasStoredAPIKey
        self.apiKeyStatusLabel = hasStoredAPIKey ? "API key configured" : "No API key saved"
        self.loginStatusLabel = hasStoredAPIKey ? "TrustedRouter developer override ready" : "TrustedRouter login required"
    }
}

public struct WorkspaceSettingsUpdate: Sendable, Hashable {
    public var apiBaseURL: String
    public var developerOverrideEnabled: Bool
    public var replacementAPIKey: String?
    public var shouldClearAPIKey: Bool

    public init(
        apiBaseURL: String,
        developerOverrideEnabled: Bool,
        replacementAPIKey: String? = nil,
        shouldClearAPIKey: Bool = false
    ) {
        self.apiBaseURL = apiBaseURL
        self.developerOverrideEnabled = developerOverrideEnabled
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
        return WorkspaceSurface(
            topBar: TopBarSurface(
                appName: topBarState.appName,
                primaryTitle: thread?.title ?? "QuillCode",
                subtitle: topBarSubtitle(thread: thread),
                modelLabel: modelLabel(for: topBarState.model),
                selectedModelID: topBarState.model,
                modelCategories: modelCategories(selectedModelID: topBarState.model),
                modeLabel: Self.modeLabel(topBarState.mode),
                agentStatus: topBarState.agentStatus,
                computerUseLabel: computerUse.available ? "Computer Use ready" : "Computer Use setup needed",
                showsComputerUseSetup: !computerUse.available
            ),
            projects: ProjectListSurface(
                items: projectItems(),
                selectedProjectID: root.selectedProjectID
            ),
            sidebar: SidebarSurface(
                items: root.sidebarItems.map { SidebarItemSurface(item: $0, selectedThreadID: root.selectedThreadID) },
                selectedThreadID: root.selectedThreadID
            ),
            transcript: TranscriptSurface(
                messages: (thread?.messages ?? []).map(MessageSurface.init),
                toolCards: toolCards
            ),
            review: reviewSurface(from: toolCards),
            terminal: TerminalSurface(
                terminal: terminal,
                cwd: activeWorkspaceRoot
            ),
            composer: ComposerSurface(composer: composer),
            commands: commands(),
            settings: WorkspaceSettingsSurface(
                config: root.config,
                hasStoredAPIKey: root.trustedRouterAPIKeyConfigured
            ),
            lastError: lastError
        )
    }

    private func topBarSubtitle(thread: ChatThread?) -> String {
        let projectName = root.topBar.projectName ?? "No project"
        guard let thread else {
            return "\(projectName) - Not started"
        }
        return "\(projectName) - \(Self.modeLabel(thread.mode)) - \(thread.model)"
    }

    private func projectItems() -> [ProjectItemSurface] {
        root.projects
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .map { ProjectItemSurface(project: $0, selectedProjectID: root.selectedProjectID) }
    }

    private func modelLabel(for id: String) -> String {
        guard let model = root.modelCatalog.first(where: { $0.id == id }) else {
            return id
        }
        if model.provider == "trustedrouter" {
            return model.id
        }
        return "\(model.provider)/\(model.displayName)"
    }

    private func modelCategories(selectedModelID: String) -> [ModelCategorySurface] {
        var catalog = root.modelCatalog
        if !catalog.contains(where: { $0.id == selectedModelID }) {
            catalog.insert(Self.fallbackModelInfo(for: selectedModelID), at: 0)
        }

        let options = catalog.map {
            ModelOptionSurface(model: $0, selectedModelID: selectedModelID)
        }
        return Dictionary(grouping: options, by: \.category)
            .map { category, models in
                ModelCategorySurface(
                    category: category,
                    models: models.sorted { lhs, rhs in
                        if lhs.provider != rhs.provider { return lhs.provider < rhs.provider }
                        return lhs.displayName < rhs.displayName
                    }
                )
            }
            .sorted {
                if $0.category == "Recommended" { return true }
                if $1.category == "Recommended" { return false }
                return $0.category < $1.category
            }
    }

    private static func fallbackModelInfo(for id: String) -> ModelInfo {
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return ModelInfo(id: id, provider: parts[0], displayName: parts[1], category: "Current")
        }
        return ModelInfo(id: id, provider: "custom", displayName: id, category: "Current")
    }

    private func commands() -> [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(id: "new-chat", title: "New chat", shortcut: "Cmd+N"),
            WorkspaceCommandSurface(id: "search", title: "Search", shortcut: "Cmd+K"),
            WorkspaceCommandSurface(id: "add-project", title: "Open project", shortcut: "Cmd+O"),
            WorkspaceCommandSurface(id: "toggle-terminal", title: "Terminal", shortcut: "Ctrl+`"),
            WorkspaceCommandSurface(id: "stop-all", title: "Stop all", shortcut: "Esc", isEnabled: composer.isSending),
            WorkspaceCommandSurface(id: "settings", title: "Settings", shortcut: "Cmd+,"),
            WorkspaceCommandSurface(
                id: "computer-use-setup",
                title: "Computer Use setup",
                isEnabled: root.topBar.computerUseStatus.available == false
            )
        ]
    }

    private func reviewSurface(from toolCards: [ToolCardState]) -> WorkspaceReviewSurface {
        guard let card = toolCards.reversed().first(where: { $0.title == "host.git.diff" }),
              card.status == .done,
              let outputJSON = card.outputJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON),
              result.ok
        else {
            return WorkspaceReviewSurface()
        }
        return GitDiffReviewParser.parse(result.stdout)
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
