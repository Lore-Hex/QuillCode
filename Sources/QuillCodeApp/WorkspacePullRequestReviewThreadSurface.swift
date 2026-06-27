import Foundation

public struct WorkspacePullRequestReviewThreadSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var isResolved: Bool
    public var isOutdated: Bool
    public var path: String?
    public var line: Int?
    public var startLine: Int?
    public var comments: [WorkspacePullRequestReviewThreadCommentSurface]
    public var selector: String?

    public var stateLabel: String {
        isResolved ? "Resolved" : "Unresolved"
    }

    public var statusLabel: String {
        let suffix = isOutdated ? " · outdated" : ""
        return "\(stateLabel)\(suffix)"
    }

    public var locationLabel: String {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return "Unknown location"
        }
        if let startLine, let line, startLine != line {
            return "\(path):\(startLine)-\(line)"
        }
        if let line = line ?? startLine {
            return "\(path):\(line)"
        }
        return path
    }

    public var summaryText: String {
        comments.first?.oneLineBody ?? "No comment text."
    }

    public var authorLabel: String? {
        comments.first?.author
    }

    public var replyDraft: String? {
        guard let commentID = comments.first?.databaseID else { return nil }
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectorPrefix = trimmedSelector.isEmpty ? "" : "\(trimmedSelector) "
        return "/pr review-reply \(selectorPrefix)\(commentID) "
    }

    public var actions: [WorkspacePullRequestReviewThreadActionSurface] {
        [
            WorkspacePullRequestReviewThreadActionSurface(
                kind: isResolved ? .unresolve : .resolve,
                threadID: id,
                selector: selector
            )
        ]
    }

    public init(
        id: String,
        isResolved: Bool,
        isOutdated: Bool = false,
        path: String? = nil,
        line: Int? = nil,
        startLine: Int? = nil,
        comments: [WorkspacePullRequestReviewThreadCommentSurface] = [],
        selector: String? = nil
    ) {
        self.id = id
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.path = path
        self.line = line
        self.startLine = startLine
        self.comments = comments
        self.selector = selector
    }
}

public struct WorkspacePullRequestReviewThreadCommentSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var databaseID: Int?
    public var author: String?
    public var body: String

    public var oneLineBody: String {
        body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public init(
        id: String,
        databaseID: Int? = nil,
        author: String? = nil,
        body: String
    ) {
        self.id = id
        self.databaseID = databaseID
        self.author = author
        self.body = body
    }
}

public enum WorkspacePullRequestReviewThreadActionKind: String, Codable, Sendable, Hashable {
    case resolve
    case unresolve

    public var title: String {
        switch self {
        case .resolve:
            return "Resolve"
        case .unresolve:
            return "Unresolve"
        }
    }

    public var systemImage: String {
        switch self {
        case .resolve:
            return "checkmark.circle"
        case .unresolve:
            return "arrow.uturn.backward.circle"
        }
    }
}

public struct WorkspacePullRequestReviewThreadActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: WorkspacePullRequestReviewThreadActionKind
    public var threadID: String
    public var selector: String?

    public var id: String {
        "\(kind.rawValue):\(threadID)"
    }

    public init(
        kind: WorkspacePullRequestReviewThreadActionKind,
        threadID: String,
        selector: String? = nil
    ) {
        self.kind = kind
        self.threadID = threadID
        self.selector = selector
    }
}
