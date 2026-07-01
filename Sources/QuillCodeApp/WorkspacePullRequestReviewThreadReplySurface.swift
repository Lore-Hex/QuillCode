import Foundation

public struct WorkspacePullRequestReviewThreadReplyTargetSurface: Codable, Sendable, Hashable, Identifiable {
    public var threadID: String
    public var commentID: Int
    public var selector: String?

    public var id: String {
        "reply:\(threadID):\(commentID)"
    }

    public init(threadID: String, commentID: Int, selector: String? = nil) {
        self.threadID = threadID
        self.commentID = commentID
        self.selector = selector
    }

    public func request(body: String) -> WorkspacePullRequestReviewThreadReplyRequest? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }
        return WorkspacePullRequestReviewThreadReplyRequest(
            threadID: threadID,
            commentID: commentID,
            body: trimmedBody,
            selector: selector
        )
    }
}

public struct WorkspacePullRequestReviewThreadReplyRequest: Codable, Sendable, Hashable, Identifiable {
    public var threadID: String
    public var commentID: Int
    public var body: String
    public var selector: String?

    public var id: String {
        "reply:\(threadID):\(commentID)"
    }

    public init(
        threadID: String,
        commentID: Int,
        body: String,
        selector: String? = nil
    ) {
        self.threadID = threadID
        self.commentID = commentID
        self.body = body
        self.selector = selector
    }
}
