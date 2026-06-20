import Foundation
import QuillCodeCore

public struct WorkspaceSurface: Codable, Sendable, Hashable {
    public var topBar: TopBarSurface
    public var projects: ProjectListSurface
    public var sidebar: SidebarSurface
    public var transcript: TranscriptSurface
    public var contextBanner: ContextBannerSurface?
    public var review: WorkspaceReviewSurface
    public var terminal: TerminalSurface
    public var browser: BrowserSurface
    public var composer: ComposerSurface
    public var commands: [WorkspaceCommandSurface]
    public var settings: WorkspaceSettingsSurface
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
        composer: ComposerSurface,
        commands: [WorkspaceCommandSurface],
        settings: WorkspaceSettingsSurface,
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
    public var instructionLabel: String
    public var instructionSources: [String]
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
        instructionLabel: String,
        instructionSources: [String],
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
        self.instructionLabel = instructionLabel
        self.instructionSources = instructionSources
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
                || item.searchText.localizedCaseInsensitiveContains(normalizedQuery)
                || pinLabel.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    public var pinnedItems: [SidebarItemSurface] {
        items.filter(\.isPinned)
    }

    public var recentItems: [SidebarItemSurface] {
        items.filter { !$0.isPinned }
    }
}

public struct SidebarItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var searchText: String
    public var actions: [SidebarItemActionSurface]
    public var isSelected: Bool
    public var isPinned: Bool

    public init(item: SidebarItem, selectedThreadID: UUID?) {
        self.id = item.id
        self.title = item.title
        self.subtitle = item.subtitle
        self.searchText = item.searchText
        self.actions = [
            SidebarItemActionSurface(
                kind: item.isPinned ? .unpin : .pin,
                threadID: item.id
            ),
            SidebarItemActionSurface(kind: .archive, threadID: item.id)
        ]
        self.isSelected = item.id == selectedThreadID
        self.isPinned = item.isPinned
    }
}

public enum SidebarItemActionKind: String, Codable, Sendable, Hashable {
    case pin
    case unpin
    case archive

    public var title: String {
        switch self {
        case .pin:
            return "Pin"
        case .unpin:
            return "Unpin"
        case .archive:
            return "Archive"
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

public struct ContextBannerSurface: Codable, Sendable, Hashable {
    public var usedPercent: Int
    public var title: String
    public var subtitle: String
    public var newThreadCommand: WorkspaceCommandSurface
    public var forkCommand: WorkspaceCommandSurface

    public init(
        usedPercent: Int,
        title: String,
        subtitle: String,
        newThreadCommand: WorkspaceCommandSurface,
        forkCommand: WorkspaceCommandSurface
    ) {
        self.usedPercent = usedPercent
        self.title = title
        self.subtitle = subtitle
        self.newThreadCommand = newThreadCommand
        self.forkCommand = forkCommand
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

public struct BrowserSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var addressDraft: String
    public var currentURL: String?
    public var title: String
    public var statusLabel: String
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
        self.title = browser.title
        self.statusLabel = browser.status
        self.comments = browser.comments.map(BrowserCommentSurface.init)
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
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

public struct WorkspaceReviewCommentSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var path: String
    public var text: String
    public var createdAt: Date

    public init(comment: WorkspaceReviewCommentState) {
        self.id = comment.id
        self.path = comment.path
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
        let activeInstructions: [ProjectInstruction]
        if let thread, !thread.instructions.isEmpty {
            activeInstructions = thread.instructions
        } else {
            activeInstructions = selectedProject?.instructions ?? []
        }
        return WorkspaceSurface(
            topBar: TopBarSurface(
                appName: topBarState.appName,
                primaryTitle: thread?.title ?? "QuillCode",
                subtitle: topBarSubtitle(thread: thread),
                instructionLabel: Self.instructionStatusLabel(for: activeInstructions),
                instructionSources: activeInstructions.map(\.path),
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
            contextBanner: contextBanner(for: thread),
            review: reviewSurface(from: toolCards, events: thread?.events ?? []),
            terminal: TerminalSurface(
                terminal: terminal,
                cwd: activeWorkspaceRoot
            ),
            browser: BrowserSurface(browser: browser),
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
        let localActionCommands = (selectedProject?.localActions ?? []).map { action in
            WorkspaceCommandSurface(
                id: action.id,
                title: "Run \(action.title)",
                isEnabled: activeWorkspaceRoot != nil
            )
        }
        return [
            WorkspaceCommandSurface(
                id: "new-chat",
                title: "New chat",
                shortcut: WorkspaceShortcutRegistry.label(for: "new-chat")
            ),
            WorkspaceCommandSurface(
                id: "fork-from-last",
                title: "Fork from last",
                isEnabled: selectedThread?.messages.isEmpty == false
            ),
            WorkspaceCommandSurface(id: "search", title: "Search", shortcut: WorkspaceShortcutRegistry.label(for: "search")),
            WorkspaceCommandSurface(
                id: "add-project",
                title: "Open project",
                shortcut: WorkspaceShortcutRegistry.label(for: "add-project")
            ),
            WorkspaceCommandSurface(
                id: "toggle-terminal",
                title: "Terminal",
                shortcut: WorkspaceShortcutRegistry.label(for: "toggle-terminal")
            ),
            WorkspaceCommandSurface(
                id: "toggle-browser",
                title: "Browser",
                shortcut: WorkspaceShortcutRegistry.label(for: "toggle-browser")
            ),
            WorkspaceCommandSurface(id: "git-pr-create", title: "Create pull request", isEnabled: activeWorkspaceRoot != nil),
            WorkspaceCommandSurface(id: "git-worktree-list", title: "List worktrees", isEnabled: activeWorkspaceRoot != nil),
            WorkspaceCommandSurface(id: "git-worktree-create", title: "Create worktree", isEnabled: activeWorkspaceRoot != nil),
            WorkspaceCommandSurface(id: "git-worktree-remove", title: "Remove worktree", isEnabled: activeWorkspaceRoot != nil),
        ] + localActionCommands + [
            WorkspaceCommandSurface(
                id: "stop-all",
                title: "Stop all",
                shortcut: WorkspaceShortcutRegistry.label(for: "stop-all"),
                isEnabled: composer.isSending || terminal.isRunning
            ),
            WorkspaceCommandSurface(id: "settings", title: "Settings", shortcut: WorkspaceShortcutRegistry.label(for: "settings")),
            WorkspaceCommandSurface(
                id: "command-palette",
                title: "Command palette",
                shortcut: WorkspaceShortcutRegistry.label(for: "command-palette")
            ),
            WorkspaceCommandSurface(
                id: "computer-use-setup",
                title: "Computer Use setup",
                isEnabled: root.topBar.computerUseStatus.available == false
            )
        ]
    }

    private func contextBanner(for thread: ChatThread?) -> ContextBannerSurface? {
        guard let thread, !thread.messages.isEmpty else { return nil }
        let usedPercent = Self.contextUsedPercent(for: thread)
        guard usedPercent >= Self.contextWarningThresholdPercent else { return nil }
        let isFull = usedPercent >= 100
        return ContextBannerSurface(
            usedPercent: usedPercent,
            title: "\(isFull ? "Context limit reached" : "Approaching context limit") (\(usedPercent)% used)",
            subtitle: "Older turns may drop out soon. Start a new thread or fork from the latest useful context.",
            newThreadCommand: WorkspaceCommandSurface(id: "new-chat", title: "New thread"),
            forkCommand: WorkspaceCommandSurface(id: "fork-from-last", title: "Fork from last")
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

    private func reviewSurface(from toolCards: [ToolCardState], events: [ThreadEvent]) -> WorkspaceReviewSurface {
        guard let card = toolCards.reversed().first(where: { $0.title == "host.git.diff" }),
              card.status == .done,
              let outputJSON = card.outputJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON),
              result.ok
        else {
            return WorkspaceReviewSurface()
        }
        var review = GitDiffReviewParser.parse(result.stdout)
        let commentsByPath = Self.reviewCommentsByPath(from: events)
        review.files = review.files.map { file in
            var file = file
            file.comments = commentsByPath[file.path] ?? []
            return file
        }
        return review
    }

    private static func reviewCommentsByPath(from events: [ThreadEvent]) -> [String: [WorkspaceReviewCommentSurface]] {
        var commentsByPath: [String: [WorkspaceReviewCommentSurface]] = [:]
        for event in events where event.kind == .reviewComment {
            guard let comment = decode(WorkspaceReviewCommentState.self, event.payloadJSON) else {
                continue
            }
            commentsByPath[comment.path, default: []].append(WorkspaceReviewCommentSurface(comment: comment))
        }
        for path in commentsByPath.keys {
            commentsByPath[path]?.sort { $0.createdAt < $1.createdAt }
        }
        return commentsByPath
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
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
