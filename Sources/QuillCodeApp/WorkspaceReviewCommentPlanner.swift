import Foundation
import QuillCodeCore

public enum WorkspaceReviewCommentSource: String, Codable, Sendable, Hashable {
    case user
    case codeReview
}

public struct WorkspaceReviewCommentState: Codable, Sendable, Hashable, Identifiable {
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

    public init(
        id: UUID = UUID(),
        path: String,
        lineNumber: Int? = nil,
        endLineNumber: Int? = nil,
        lineKind: WorkspaceReviewLineKind? = nil,
        text: String,
        createdAt: Date = Date(),
        source: WorkspaceReviewCommentSource? = .user,
        priority: WorkspaceCodeReviewPriority? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.path = path
        self.lineNumber = lineNumber
        self.endLineNumber = endLineNumber
        self.lineKind = lineKind
        self.text = text
        self.createdAt = createdAt
        self.source = source
        self.priority = priority
        self.title = title
    }
}

struct WorkspaceReviewCommentPlanner: Sendable, Hashable {
    static func event(for finding: WorkspaceCodeReviewFinding, createdAt: Date = Date()) -> ThreadEvent {
        let comment = WorkspaceReviewCommentState(
            path: finding.path,
            lineNumber: finding.line,
            endLineNumber: finding.endLine,
            text: finding.body,
            createdAt: createdAt,
            source: .codeReview,
            priority: finding.priority,
            title: finding.title
        )
        return ThreadEvent(
            kind: .reviewComment,
            createdAt: createdAt,
            summary: "\(finding.priority.label) finding in \(finding.path)",
            payloadJSON: (try? JSONHelpers.encodePretty(comment)) ?? "{}"
        )
    }

    static func event(
        path: String,
        lineNumber: Int? = nil,
        endLineNumber: Int? = nil,
        lineKind: WorkspaceReviewLineKind? = nil,
        text: String,
        review: WorkspaceReviewSurface,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> ThreadEvent? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !trimmedText.isEmpty,
              let file = review.files.first(where: { $0.path == trimmedPath })
        else {
            return nil
        }

        guard endLineNumber == nil || lineNumber != nil else {
            return nil
        }

        let normalizedRange = normalizedRange(lineNumber: lineNumber, endLineNumber: endLineNumber)
        guard lineNumber == nil || normalizedRange != nil else {
            return nil
        }
        if let normalizedRange {
            guard rangeExists(normalizedRange, lineKind: lineKind, in: file) else {
                return nil
            }
        }

        let comment = WorkspaceReviewCommentState(
            id: id,
            path: trimmedPath,
            lineNumber: normalizedRange?.lowerBound,
            endLineNumber: normalizedRange?.upperBound,
            lineKind: lineKind,
            text: trimmedText,
            createdAt: createdAt
        )
        return ThreadEvent(
            kind: .reviewComment,
            summary: summary(path: trimmedPath, range: normalizedRange),
            payloadJSON: (try? JSONHelpers.encodePretty(comment)) ?? "{}"
        )
    }

    private static func normalizedRange(
        lineNumber: Int?,
        endLineNumber: Int?
    ) -> ClosedRange<Int>? {
        guard let lineNumber else { return nil }
        let endLineNumber = endLineNumber ?? lineNumber
        guard lineNumber > 0, endLineNumber > 0 else { return nil }
        return min(lineNumber, endLineNumber)...max(lineNumber, endLineNumber)
    }

    private static func rangeExists(
        _ range: ClosedRange<Int>,
        lineKind: WorkspaceReviewLineKind?,
        in file: WorkspaceReviewFileSurface
    ) -> Bool {
        let lines = file.hunkItems.flatMap(\.lines)
        guard lines.contains(where: {
            $0.displayLineNumber == range.lowerBound
                && (lineKind == nil || $0.kind == lineKind)
        }) else {
            return false
        }
        return range.allSatisfy { number in
            lines.contains { $0.displayLineNumber == number }
        }
    }

    private static func summary(path: String, range: ClosedRange<Int>?) -> String {
        guard let range else {
            return "Commented on \(path)"
        }
        return range.lowerBound == range.upperBound
            ? "Commented on \(path):\(range.lowerBound)"
            : "Commented on \(path):\(range.lowerBound)-\(range.upperBound)"
    }
}
