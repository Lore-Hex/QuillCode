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
    public var extensions: WorkspaceExtensionsSurface
    public var memories: WorkspaceMemoriesSurface
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
        extensions: WorkspaceExtensionsSurface = WorkspaceExtensionsSurface(),
        memories: WorkspaceMemoriesSurface = WorkspaceMemoriesSurface(),
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
        self.extensions = extensions
        self.memories = memories
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
    public var memoryLabel: String
    public var memorySources: [String]
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
        memoryLabel: String,
        memorySources: [String],
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
        self.memoryLabel = memoryLabel
        self.memorySources = memorySources
        self.modelLabel = modelLabel
        self.selectedModelID = selectedModelID
        self.modelCategories = modelCategories
        self.modeLabel = modeLabel
        self.agentStatus = agentStatus
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

        return modelCategories.compactMap { category in
            let models = category.models.filter { option in
                let haystack = [
                    category.category,
                    option.id,
                    option.provider,
                    option.displayName
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
    public var summary: String
    public var details: [String]

    public init(snapshot: BrowserSnapshotState) {
        self.sourceLabel = snapshot.sourceLabel
        self.summary = snapshot.summary
        self.details = snapshot.details
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
        emptyTitle: String = "No extension manifests found",
        emptySubtitle: String = "Add JSON manifests under .quillcode/plugins, .quillcode/skills, or .quillcode/mcp."
    ) {
        self.isVisible = isVisible
        self.items = manifests.map {
            ProjectExtensionManifestSurface(
                manifest: $0,
                mcpServerStatus: mcpServerStatuses[$0.id] ?? .stopped
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
    public var relativePath: String
    public var statusLabel: String
    public var transportLabel: String?
    public var launchCommand: String?
    public var canStart: Bool
    public var canStop: Bool
    public var startCommandID: String?
    public var stopCommandID: String?

    public init(
        manifest: ProjectExtensionManifest,
        mcpServerStatus: MCPServerLifecycleStatus = .stopped
    ) {
        self.id = manifest.id
        self.kind = manifest.kind
        self.kindLabel = manifest.kind.title
        self.name = manifest.name
        self.summary = manifest.summary
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
        self.canStart = manifest.kind == .mcpServer
            && manifest.isEnabled
            && manifest.launchExecutable != nil
            && mcpServerStatus != .running
        self.canStop = manifest.kind == .mcpServer && mcpServerStatus == .running
        self.startCommandID = canStart ? "mcp-start:\(manifest.id)" : nil
        self.stopCommandID = canStop ? "mcp-stop:\(manifest.id)" : nil
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

public struct WorkspaceCommandGroupSurface: Sendable, Hashable, Identifiable {
    public var id: String { title }
    public var title: String
    public var commands: [WorkspaceCommandSurface]
}

public enum WorkspaceCommandPalette {
    public static let threadCategory = "Thread"
    public static let navigationCategory = "Navigation"
    public static let workspaceCategory = "Workspace"
    public static let gitCategory = "Git"
    public static let environmentCategory = "Environment"
    public static let controlCategory = "Control"
    public static let computerUseCategory = "Computer Use"
    public static let extensionsCategory = "Extensions"
    public static let memoriesCategory = "Memories"

    public static let categoryOrder = [
        threadCategory,
        navigationCategory,
        workspaceCategory,
        memoriesCategory,
        extensionsCategory,
        gitCategory,
        environmentCategory,
        controlCategory,
        computerUseCategory
    ]

    public static func rankedCommands(
        _ commands: [WorkspaceCommandSurface],
        matching query: String
    ) -> [WorkspaceCommandSurface] {
        let normalizedQuery = normalize(query)
        let scoredCommands = commands.enumerated().compactMap { index, command in
            score(command, query: normalizedQuery).map { score in
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
        if category.contains(query) {
            return 440
        }
        return nil
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

public struct WorkspaceSettingsSurface: Codable, Sendable, Hashable {
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var hasStoredAPIKey: Bool
    public var signInURL: String
    public var apiKeyStatusLabel: String
    public var loginStatusLabel: String
    public var accountLabel: String?

    public init(config: AppConfig, hasStoredAPIKey: Bool) {
        self.apiBaseURL = config.apiBaseURL
        self.authMode = config.authMode
        self.developerOverrideEnabled = config.developerOverrideEnabled
        self.hasStoredAPIKey = hasStoredAPIKey
        self.signInURL = TrustedRouterDefaults.loopbackCallbackURL
        self.accountLabel = config.trustedRouterAccount?.displayLabel
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
        return WorkspaceSurface(
            topBar: TopBarSurface(
                appName: topBarState.appName,
                primaryTitle: thread?.title ?? "QuillCode",
                subtitle: topBarSubtitle(thread: thread),
                instructionLabel: Self.instructionStatusLabel(for: activeInstructions),
                instructionSources: activeInstructions.map(\.path),
                memoryLabel: Self.memoryStatusLabel(for: activeMemories),
                memorySources: activeMemories.map(\.relativePath),
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
                toolCards: toolCards,
                timelineItems: thread.map(Self.transcriptTimelineItems(for:))
            ),
            contextBanner: contextBanner(for: thread),
            review: reviewSurface(from: toolCards, events: thread?.events ?? []),
            terminal: TerminalSurface(
                terminal: terminal,
                cwd: activeWorkspaceRoot
            ),
            browser: BrowserSurface(browser: browser),
            extensions: WorkspaceExtensionsSurface(
                isVisible: extensions.isVisible,
                manifests: selectedProject?.extensionManifests ?? [],
                mcpServerStatuses: extensions.mcpServerStatuses
            ),
            memories: WorkspaceMemoriesSurface(
                isVisible: memories.isVisible,
                notes: activeMemories
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
        let localActionCommands = (selectedProject?.localActions ?? []).map { action in
            WorkspaceCommandSurface(
                id: action.id,
                title: "Run \(action.title)",
                category: WorkspaceCommandPalette.environmentCategory,
                keywords: ["local environment", "script", "bootstrap", action.title],
                isEnabled: activeWorkspaceRoot != nil
            )
        }
        let mcpLifecycleCommands = (selectedProject?.extensionManifests ?? [])
            .filter { $0.kind == .mcpServer }
            .flatMap { manifest -> [WorkspaceCommandSurface] in
                let status = extensions.mcpServerStatuses[manifest.id] ?? .stopped
                let canStart = manifest.isEnabled
                    && manifest.launchExecutable != nil
                    && status != .running
                    && activeWorkspaceRoot != nil
                let canStop = status == .running
                return [
                    WorkspaceCommandSurface(
                        id: "mcp-start:\(manifest.id)",
                        title: "Start \(manifest.name)",
                        category: WorkspaceCommandPalette.extensionsCategory,
                        keywords: ["mcp", "server", "start", "stdio", manifest.name],
                        isEnabled: canStart
                    ),
                    WorkspaceCommandSurface(
                        id: "mcp-stop:\(manifest.id)",
                        title: "Stop \(manifest.name)",
                        category: WorkspaceCommandPalette.extensionsCategory,
                        keywords: ["mcp", "server", "stop", "stdio", manifest.name],
                        isEnabled: canStop
                    )
                ]
            }
        return [
            WorkspaceCommandSurface(
                id: "new-chat",
                title: "New chat",
                shortcut: WorkspaceShortcutRegistry.label(for: "new-chat"),
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "conversation"]
            ),
            WorkspaceCommandSurface(
                id: "fork-from-last",
                title: "Fork from last",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "context", "continue"],
                isEnabled: selectedThread?.messages.isEmpty == false
            ),
            WorkspaceCommandSurface(
                id: "search",
                title: "Search",
                shortcut: WorkspaceShortcutRegistry.label(for: "search"),
                category: WorkspaceCommandPalette.navigationCategory,
                keywords: ["find", "threads", "chat"]
            ),
            WorkspaceCommandSurface(
                id: "add-project",
                title: "Open project",
                shortcut: WorkspaceShortcutRegistry.label(for: "add-project"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["folder", "workspace", "repo"]
            ),
            WorkspaceCommandSurface(
                id: "toggle-terminal",
                title: "Terminal",
                shortcut: WorkspaceShortcutRegistry.label(for: "toggle-terminal"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["shell", "command", "pty"]
            ),
            WorkspaceCommandSurface(
                id: "toggle-browser",
                title: "Browser",
                shortcut: WorkspaceShortcutRegistry.label(for: "toggle-browser"),
                category: WorkspaceCommandPalette.workspaceCategory,
                keywords: ["preview", "web", "localhost"]
            ),
            WorkspaceCommandSurface(
                id: "toggle-memories",
                title: "Memories",
                category: WorkspaceCommandPalette.memoriesCategory,
                keywords: ["memory", "context", "preferences", "facts"]
            ),
            WorkspaceCommandSurface(
                id: "memory-add",
                title: "Add memory",
                category: WorkspaceCommandPalette.memoriesCategory,
                keywords: ["remember", "save", "preference", "fact"]
            ),
            WorkspaceCommandSurface(
                id: "toggle-extensions",
                title: "Extensions",
                category: WorkspaceCommandPalette.extensionsCategory,
                keywords: ["plugins", "skills", "mcp", "manifest"],
                isEnabled: activeWorkspaceRoot != nil
            ),
            WorkspaceCommandSurface(
                id: "git-pr-create",
                title: "Create pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "review"],
                isEnabled: activeWorkspaceRoot != nil
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-list",
                title: "List worktrees",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace"],
                isEnabled: activeWorkspaceRoot != nil
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-create",
                title: "Create worktree",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace"],
                isEnabled: activeWorkspaceRoot != nil
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-remove",
                title: "Remove worktree",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace", "delete"],
                isEnabled: activeWorkspaceRoot != nil
            ),
        ] + localActionCommands + mcpLifecycleCommands + [
            WorkspaceCommandSurface(
                id: "stop-all",
                title: "Stop all",
                shortcut: WorkspaceShortcutRegistry.label(for: "stop-all"),
                category: WorkspaceCommandPalette.controlCategory,
                keywords: ["cancel", "abort", "halt"],
                isEnabled: composer.isSending
                    || terminal.isRunning
                    || extensions.mcpServerStatuses.values.contains(.running)
            ),
            WorkspaceCommandSurface(
                id: "settings",
                title: "Settings",
                shortcut: WorkspaceShortcutRegistry.label(for: "settings"),
                category: WorkspaceCommandPalette.navigationCategory,
                keywords: ["preferences", "trustedrouter", "auth"]
            ),
            WorkspaceCommandSurface(
                id: "command-palette",
                title: "Command palette",
                shortcut: WorkspaceShortcutRegistry.label(for: "command-palette"),
                category: WorkspaceCommandPalette.navigationCategory,
                keywords: ["commands", "actions"]
            ),
            WorkspaceCommandSurface(
                id: "computer-use-setup",
                title: "Computer Use setup",
                category: WorkspaceCommandPalette.computerUseCategory,
                keywords: ["screen", "accessibility", "permissions"],
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
        let commentBuckets = Self.reviewCommentBuckets(from: events)
        review.files = review.files.map { file in
            var file = file
            file.comments = commentBuckets.fileCommentsByPath[file.path] ?? []
            file.hunkItems = file.hunkItems.map { hunk in
                var hunk = hunk
                hunk.lines = hunk.lines.map { line in
                    var line = line
                    if let displayLineNumber = line.displayLineNumber {
                        line.comments = commentBuckets.lineCommentsByPath[file.path]?[displayLineNumber]?.filter { comment in
                            comment.lineKind == nil || comment.lineKind == line.kind
                        } ?? []
                    }
                    return line
                }
                return hunk
            }
            return file
        }
        return review
    }

    private struct ReviewCommentBuckets {
        var fileCommentsByPath: [String: [WorkspaceReviewCommentSurface]] = [:]
        var lineCommentsByPath: [String: [Int: [WorkspaceReviewCommentSurface]]] = [:]
    }

    private static func reviewCommentBuckets(from events: [ThreadEvent]) -> ReviewCommentBuckets {
        var buckets = ReviewCommentBuckets()
        for event in events where event.kind == .reviewComment {
            guard let comment = decode(WorkspaceReviewCommentState.self, event.payloadJSON) else {
                continue
            }
            let surface = WorkspaceReviewCommentSurface(comment: comment)
            if let lineNumber = comment.lineNumber {
                buckets.lineCommentsByPath[comment.path, default: [:]][lineNumber, default: []].append(surface)
            } else {
                buckets.fileCommentsByPath[comment.path, default: []].append(surface)
            }
        }
        for path in buckets.fileCommentsByPath.keys {
            buckets.fileCommentsByPath[path]?.sort { $0.createdAt < $1.createdAt }
        }
        for path in buckets.lineCommentsByPath.keys {
            guard let lineNumbers = buckets.lineCommentsByPath[path]?.keys else {
                continue
            }
            for lineNumber in lineNumbers {
                buckets.lineCommentsByPath[path]?[lineNumber]?.sort { $0.createdAt < $1.createdAt }
            }
        }
        return buckets
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
