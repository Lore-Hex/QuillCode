import Foundation
import QuillCodeReview

public struct WorkspaceReviewCommentSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var path: String
    public var lineNumber: Int?
    public var endLineNumber: Int?
    public var lineKind: WorkspaceReviewLineKind?
    public var text: String
    public var createdAt: Date
    public var source: WorkspaceReviewCommentSource?
    public var priority: WorkspaceCodeReviewPriority?
    public var title: String?

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
        self.source = comment.source
        self.priority = comment.priority
        self.title = comment.title
    }
}
