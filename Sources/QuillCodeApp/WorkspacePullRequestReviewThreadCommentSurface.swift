import Foundation

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
