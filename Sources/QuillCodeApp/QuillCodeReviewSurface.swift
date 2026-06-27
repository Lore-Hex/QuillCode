import Foundation

public struct WorkspaceReviewSurface: Codable, Sendable, Hashable {
    public var title: String
    public var subtitle: String
    public var files: [WorkspaceReviewFileSurface]
    public var pullRequestThreads: [WorkspacePullRequestReviewThreadSurface]
    public var totalInsertions: Int
    public var totalDeletions: Int
    public var totalHunks: Int

    public var isVisible: Bool {
        !files.isEmpty || !pullRequestThreads.isEmpty
    }

    public var badgeLabel: String {
        let parts = [
            files.isEmpty ? nil : "\(totalHunks) hunk\(totalHunks == 1 ? "" : "s")",
            pullRequestThreads.isEmpty ? nil : "\(pullRequestThreads.count) thread\(pullRequestThreads.count == 1 ? "" : "s")"
        ].compactMap(\.self)
        return parts.isEmpty ? "Review" : parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case files
        case pullRequestThreads
        case totalInsertions
        case totalDeletions
        case totalHunks
    }

    public init(
        title: String = "Review changes",
        subtitle: String = "Latest git diff",
        files: [WorkspaceReviewFileSurface] = [],
        pullRequestThreads: [WorkspacePullRequestReviewThreadSurface] = []
    ) {
        self.title = title
        self.files = files
        self.pullRequestThreads = pullRequestThreads
        self.totalInsertions = files.reduce(0) { $0 + $1.insertions }
        self.totalDeletions = files.reduce(0) { $0 + $1.deletions }
        self.totalHunks = files.reduce(0) { $0 + $1.hunks }
        if !files.isEmpty {
            self.subtitle = "\(files.count) file\(files.count == 1 ? "" : "s") changed, +\(totalInsertions) -\(totalDeletions)"
        } else if !pullRequestThreads.isEmpty {
            let unresolvedCount = pullRequestThreads.filter { !$0.isResolved }.count
            let resolvedCount = pullRequestThreads.count - unresolvedCount
            self.subtitle = "\(pullRequestThreads.count) review thread\(pullRequestThreads.count == 1 ? "" : "s"), \(unresolvedCount) unresolved, \(resolvedCount) resolved"
        } else {
            self.subtitle = subtitle
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.files = try container.decode([WorkspaceReviewFileSurface].self, forKey: .files)
        self.pullRequestThreads = try container.decodeIfPresent(
            [WorkspacePullRequestReviewThreadSurface].self,
            forKey: .pullRequestThreads
        ) ?? []
        self.totalInsertions = try container.decode(Int.self, forKey: .totalInsertions)
        self.totalDeletions = try container.decode(Int.self, forKey: .totalDeletions)
        self.totalHunks = try container.decode(Int.self, forKey: .totalHunks)
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
