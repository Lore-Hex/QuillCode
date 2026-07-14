import Foundation
import QuillCodeCore

public struct SidebarThreadSectionSurface: Codable, Sendable, Hashable, Identifiable {
    public var title: String
    public var items: [SidebarItemSurface]

    public var id: String { title }

    public init(title: String, items: [SidebarItemSurface]) {
        self.title = title
        self.items = items
    }
}

/// A thread's worktree binding, summarized for the sidebar row: the branch it runs on and whether the
/// worktree directory still exists (a dangling binding falls back to the project root, so the row warns).
public struct SidebarItemWorktreeSummary: Codable, Sendable, Hashable {
    public var branch: String
    public var branchLeaf: String
    public var isResolvable: Bool
    public var location: WorktreeExecutionLocation
    public var hasRestorableSnapshot: Bool

    public init(
        branch: String,
        branchLeaf: String,
        isResolvable: Bool,
        location: WorktreeExecutionLocation = .worktree,
        hasRestorableSnapshot: Bool = false
    ) {
        self.branch = branch
        self.branchLeaf = branchLeaf
        self.isResolvable = isResolvable
        self.location = location
        self.hasRestorableSnapshot = hasRestorableSnapshot
    }

    private enum CodingKeys: String, CodingKey {
        case branch
        case branchLeaf
        case isResolvable
        case location
        case hasRestorableSnapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.branch = try container.decode(String.self, forKey: .branch)
        self.branchLeaf = try container.decode(String.self, forKey: .branchLeaf)
        self.isResolvable = try container.decode(Bool.self, forKey: .isResolvable)
        self.location = try container.decodeIfPresent(
            WorktreeExecutionLocation.self,
            forKey: .location
        ) ?? .worktree
        self.hasRestorableSnapshot = try container.decodeIfPresent(Bool.self, forKey: .hasRestorableSnapshot) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(branch, forKey: .branch)
        try container.encode(branchLeaf, forKey: .branchLeaf)
        try container.encode(isResolvable, forKey: .isResolvable)
        try container.encode(location, forKey: .location)
        try container.encode(hasRestorableSnapshot, forKey: .hasRestorableSnapshot)
    }
}

public struct SidebarItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var searchText: String
    public var updatedAt: Date
    public var actions: [SidebarItemActionSurface]
    public var isSelected: Bool
    public var isBulkSelected: Bool
    public var isPinned: Bool
    public var isArchived: Bool
    public var worktree: SidebarItemWorktreeSummary?
    public var pullRequest: PullRequestLink?
    /// Live, session-only agent status for this chat. nil means no task currently owns the chat.
    public var runStatusLabel: String?

    public var isRunning: Bool { runStatusLabel != nil }

    public init(
        item: SidebarItem,
        selectedThreadID: UUID?,
        selectedThreadIDs: Set<UUID> = [],
        runStatusLabel: String? = nil
    ) {
        self.id = item.id
        self.title = item.title
        self.subtitle = item.subtitle
        self.searchText = item.searchText
        self.updatedAt = item.updatedAt
        self.actions = Self.actions(for: item, isRunning: runStatusLabel != nil)
        self.isSelected = item.id == selectedThreadID
        self.isBulkSelected = selectedThreadIDs.contains(item.id)
        self.isPinned = item.isPinned
        self.isArchived = item.isArchived
        self.worktree = item.worktree
        self.pullRequest = item.pullRequest
        self.runStatusLabel = runStatusLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case searchText
        case updatedAt
        case actions
        case isSelected
        case isBulkSelected
        case isPinned
        case isArchived
        case worktree
        case pullRequest
        case runStatusLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.searchText = try container.decode(String.self, forKey: .searchText)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        self.actions = try container.decodeIfPresent([SidebarItemActionSurface].self, forKey: .actions) ?? []
        self.isSelected = try container.decode(Bool.self, forKey: .isSelected)
        self.isBulkSelected = try container.decodeIfPresent(Bool.self, forKey: .isBulkSelected) ?? false
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.worktree = try container.decodeIfPresent(SidebarItemWorktreeSummary.self, forKey: .worktree)
        self.pullRequest = try container.decodeIfPresent(PullRequestLink.self, forKey: .pullRequest)
        self.runStatusLabel = try container.decodeIfPresent(String.self, forKey: .runStatusLabel)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(searchText, forKey: .searchText)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(actions, forKey: .actions)
        try container.encode(isSelected, forKey: .isSelected)
        try container.encode(isBulkSelected, forKey: .isBulkSelected)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encodeIfPresent(worktree, forKey: .worktree)
        try container.encodeIfPresent(pullRequest, forKey: .pullRequest)
        try container.encodeIfPresent(runStatusLabel, forKey: .runStatusLabel)
    }

    private static func actions(for item: SidebarItem, isRunning: Bool) -> [SidebarItemActionSurface] {
        if item.isArchived {
            var actions = [SidebarItemActionSurface(kind: .unarchive, threadID: item.id)]
            if !isRunning {
                actions.append(SidebarItemActionSurface(kind: .delete, threadID: item.id))
            }
            return actions
        }
        var actions = [
            SidebarItemActionSurface(kind: .rename, threadID: item.id),
            SidebarItemActionSurface(
                kind: item.isPinned ? .unpin : .pin,
                threadID: item.id
            ),
            SidebarItemActionSurface(kind: .archive, threadID: item.id)
        ]
        if !isRunning {
            actions.insert(SidebarItemActionSurface(kind: .duplicate, threadID: item.id), at: 1)
            actions.append(SidebarItemActionSurface(kind: .delete, threadID: item.id))
        }
        return actions
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
