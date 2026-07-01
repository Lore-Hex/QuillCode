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

    public var replyTarget: WorkspacePullRequestReviewThreadReplyTargetSurface? {
        guard let commentID = comments.first?.databaseID else { return nil }
        return WorkspacePullRequestReviewThreadReplyTargetSurface(
            threadID: id,
            commentID: commentID,
            selector: selector
        )
    }

    public func replyRequest(body: String) -> WorkspacePullRequestReviewThreadReplyRequest? {
        guard let replyTarget else { return nil }
        return replyTarget.request(body: body)
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
