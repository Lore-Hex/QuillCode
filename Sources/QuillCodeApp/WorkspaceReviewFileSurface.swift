import Foundation

public struct WorkspaceReviewFileSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var insertions: Int
    public var deletions: Int
    public var hunks: Int
    public var isBinary: Bool
    public var isDeleted: Bool
    public var hunkItems: [WorkspaceReviewHunkSurface]
    public var comments: [WorkspaceReviewCommentSurface]

    private enum CodingKeys: String, CodingKey {
        case path
        case insertions
        case deletions
        case hunks
        case isBinary
        case isDeleted
        case hunkItems
        case comments
    }

    public var changeLabel: String {
        var parts = ["+\(insertions)", "-\(deletions)"]
        if hunks > 0 {
            parts.append("\(hunks) hunk\(hunks == 1 ? "" : "s")")
        }
        if isBinary {
            parts.append("binary")
        }
        if isDeleted {
            parts.append("deleted")
        }
        return parts.joined(separator: " · ")
    }

    public var unreadableReason: String? {
        if isDeleted {
            return "Deleted file"
        }
        if isBinary {
            return "Binary file"
        }
        return nil
    }

    public var actions: [WorkspaceReviewActionSurface] {
        actions(in: .unstaged)
    }

    public func actions(in scope: WorkspaceReviewScope) -> [WorkspaceReviewActionSurface] {
        let mutatingActions: [WorkspaceReviewActionSurface]
        switch scope {
        case .unstaged:
            mutatingActions = [
                WorkspaceReviewActionSurface(kind: .stage, path: path, scope: scope),
                WorkspaceReviewActionSurface(kind: .restore, path: path, scope: scope)
            ]
        case .staged:
            mutatingActions = [
                WorkspaceReviewActionSurface(kind: .unstage, path: path, scope: scope)
            ]
        case .commit, .branch, .lastTurn:
            mutatingActions = []
        }
        guard unreadableReason == nil else {
            return mutatingActions
        }
        return [WorkspaceReviewActionSurface(kind: .open, path: path, scope: scope)] + mutatingActions
    }

    public init(
        path: String,
        insertions: Int,
        deletions: Int,
        hunks: Int,
        isBinary: Bool = false,
        isDeleted: Bool = false,
        hunkItems: [WorkspaceReviewHunkSurface] = [],
        comments: [WorkspaceReviewCommentSurface] = []
    ) {
        self.path = path
        self.insertions = insertions
        self.deletions = deletions
        self.hunks = hunks
        self.isBinary = isBinary
        self.isDeleted = isDeleted
        self.hunkItems = hunkItems
        self.comments = comments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.insertions = try container.decode(Int.self, forKey: .insertions)
        self.deletions = try container.decode(Int.self, forKey: .deletions)
        self.hunks = try container.decode(Int.self, forKey: .hunks)
        self.isBinary = try container.decodeIfPresent(Bool.self, forKey: .isBinary) ?? false
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.hunkItems = try container.decodeIfPresent([WorkspaceReviewHunkSurface].self, forKey: .hunkItems) ?? []
        self.comments = try container.decodeIfPresent([WorkspaceReviewCommentSurface].self, forKey: .comments) ?? []
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
        actions(in: .unstaged)
    }

    public func actions(in scope: WorkspaceReviewScope) -> [WorkspaceReviewActionSurface] {
        switch scope {
        case .unstaged:
            return [
                WorkspaceReviewActionSurface(
                    kind: .stageHunk,
                    path: path,
                    patch: patch,
                    targetID: id,
                    scope: scope
                ),
                WorkspaceReviewActionSurface(
                    kind: .restoreHunk,
                    path: path,
                    patch: patch,
                    targetID: id,
                    scope: scope
                )
            ]
        case .staged:
            return [
                WorkspaceReviewActionSurface(
                    kind: .unstageHunk,
                    path: path,
                    patch: patch,
                    targetID: id,
                    scope: scope
                )
            ]
        case .commit, .branch, .lastTurn:
            return []
        }
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
