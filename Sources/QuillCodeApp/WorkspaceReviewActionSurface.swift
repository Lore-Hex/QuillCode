import Foundation

public enum WorkspaceReviewActionKind: String, Codable, Sendable, Hashable {
    case open
    case stage
    case unstage
    case restore
    case stageHunk = "stage_hunk"
    case unstageHunk = "unstage_hunk"
    case restoreHunk = "restore_hunk"
    case stageAll = "stage_all"
    case unstageAll = "unstage_all"
    case restoreAll = "restore_all"
    case revertTurn = "revert_turn"

    public var title: String {
        switch self {
        case .open:
            return "Open"
        case .stage:
            return "Stage"
        case .unstage:
            return "Unstage"
        case .restore:
            return "Restore"
        case .stageHunk:
            return "Stage hunk"
        case .unstageHunk:
            return "Unstage hunk"
        case .restoreHunk:
            return "Restore hunk"
        case .stageAll:
            return "Stage all"
        case .unstageAll:
            return "Unstage all"
        case .restoreAll, .revertTurn:
            return "Revert all"
        }
    }

    public var systemImage: String {
        switch self {
        case .open:
            return "doc.text"
        case .stage:
            return "plus.rectangle.on.folder"
        case .unstage:
            return "minus.rectangle.on.folder"
        case .restore:
            return "arrow.uturn.backward"
        case .stageHunk:
            return "plus.square.on.square"
        case .unstageHunk:
            return "minus.square.on.square"
        case .restoreHunk:
            return "arrow.uturn.left.square"
        case .stageAll:
            return "plus.rectangle.on.folder"
        case .unstageAll:
            return "minus.rectangle.on.folder"
        case .restoreAll, .revertTurn:
            return "arrow.uturn.backward.circle"
        }
    }

    /// Whether the action changes the working tree/index and therefore needs a diff
    /// refresh. `.open` only reads a file, so it pairs no refresh and never clears
    /// the review pane.
    public var isMutating: Bool {
        switch self {
        case .open:
            return false
        case .stage, .unstage, .restore, .stageHunk, .unstageHunk, .restoreHunk,
             .stageAll, .unstageAll, .restoreAll, .revertTurn:
            return true
        }
    }
}

public struct WorkspaceReviewActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: WorkspaceReviewActionKind
    public var path: String
    public var patch: String?
    public var targetID: String?
    public var scope: WorkspaceReviewScope
    /// Exact visible paths affected by a whole-diff action. File/hunk actions leave this empty
    /// and continue to use `path`; the split keeps existing encoded actions compatible.
    public var paths: [String]
    /// The assistant turn to reverse for a Last-turn whole-diff revert.
    public var turnMessageID: UUID?

    public var id: String {
        "\(kind.rawValue):\(path):\(targetID ?? "file")"
    }

    public init(
        kind: WorkspaceReviewActionKind,
        path: String,
        patch: String? = nil,
        targetID: String? = nil,
        scope: WorkspaceReviewScope = .unstaged,
        paths: [String] = [],
        turnMessageID: UUID? = nil
    ) {
        self.kind = kind
        self.path = path
        self.patch = patch
        self.targetID = targetID
        self.scope = scope
        self.paths = paths
        self.turnMessageID = turnMessageID
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case patch
        case targetID
        case scope
        case paths
        case turnMessageID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(WorkspaceReviewActionKind.self, forKey: .kind)
        self.path = try container.decode(String.self, forKey: .path)
        self.patch = try container.decodeIfPresent(String.self, forKey: .patch)
        self.targetID = try container.decodeIfPresent(String.self, forKey: .targetID)
        self.scope = try container.decodeIfPresent(WorkspaceReviewScope.self, forKey: .scope) ?? .unstaged
        self.paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
        self.turnMessageID = try container.decodeIfPresent(UUID.self, forKey: .turnMessageID)
    }
}
