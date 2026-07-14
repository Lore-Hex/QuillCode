import Foundation

public enum WorkspaceReviewActionKind: String, Codable, Sendable, Hashable {
    case open
    case stage
    case unstage
    case restore
    case stageHunk = "stage_hunk"
    case unstageHunk = "unstage_hunk"
    case restoreHunk = "restore_hunk"

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
        }
    }

    /// Whether the action changes the working tree/index and therefore needs a diff
    /// refresh. `.open` only reads a file, so it pairs no refresh and never clears
    /// the review pane.
    public var isMutating: Bool {
        switch self {
        case .open:
            return false
        case .stage, .unstage, .restore, .stageHunk, .unstageHunk, .restoreHunk:
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

    public var id: String {
        "\(kind.rawValue):\(path):\(targetID ?? "file")"
    }

    public init(
        kind: WorkspaceReviewActionKind,
        path: String,
        patch: String? = nil,
        targetID: String? = nil,
        scope: WorkspaceReviewScope = .unstaged
    ) {
        self.kind = kind
        self.path = path
        self.patch = patch
        self.targetID = targetID
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case patch
        case targetID
        case scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(WorkspaceReviewActionKind.self, forKey: .kind)
        self.path = try container.decode(String.self, forKey: .path)
        self.patch = try container.decodeIfPresent(String.self, forKey: .patch)
        self.targetID = try container.decodeIfPresent(String.self, forKey: .targetID)
        self.scope = try container.decodeIfPresent(WorkspaceReviewScope.self, forKey: .scope) ?? .unstaged
    }
}
