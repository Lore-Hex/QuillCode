import Foundation
import QuillCodeCore

struct WorkspaceReviewSurfaceBuilder: Sendable, Hashable {
    var toolCards: [ToolCardState]
    var events: [ThreadEvent]

    func surface() -> WorkspaceReviewSurface {
        guard let result = latestCompletedGitDiffResult else {
            return WorkspaceReviewSurface()
        }

        var review = GitDiffReviewParser.parse(result.stdout)
        let commentBuckets = Self.reviewCommentBuckets(from: events)
        review.files = review.files.map { file in
            var file = file
            file.comments = commentBuckets.fileCommentsByPath[file.path] ?? []
            file.hunkItems = file.hunkItems.map { hunk in
                var hunk = hunk
                hunk.lines = hunk.lines.map { line in
                    var line = line
                    if let displayLineNumber = line.displayLineNumber {
                        line.comments = commentBuckets.lineCommentsByPath[file.path]?[displayLineNumber]?.filter { comment in
                            comment.lineKind == nil || comment.lineKind == line.kind
                        } ?? []
                    }
                    return line
                }
                return hunk
            }
            return file
        }
        return review
    }

    private var latestCompletedGitDiffResult: ToolResult? {
        guard let card = toolCards.reversed().first(where: { $0.title == "host.git.diff" }),
              card.status == .done,
              let outputJSON = card.outputJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON),
              result.ok
        else {
            return nil
        }
        return result
    }

    private struct ReviewCommentBuckets: Sendable, Hashable {
        var fileCommentsByPath: [String: [WorkspaceReviewCommentSurface]] = [:]
        var lineCommentsByPath: [String: [Int: [WorkspaceReviewCommentSurface]]] = [:]
    }

    private static func reviewCommentBuckets(from events: [ThreadEvent]) -> ReviewCommentBuckets {
        var buckets = ReviewCommentBuckets()
        for event in events where event.kind == .reviewComment {
            guard let comment = decode(WorkspaceReviewCommentState.self, event.payloadJSON) else {
                continue
            }
            let surface = WorkspaceReviewCommentSurface(comment: comment)
            if let lineNumber = comment.lineNumber {
                buckets.lineCommentsByPath[comment.path, default: [:]][lineNumber, default: []].append(surface)
            } else {
                buckets.fileCommentsByPath[comment.path, default: []].append(surface)
            }
        }
        for path in buckets.fileCommentsByPath.keys {
            buckets.fileCommentsByPath[path]?.sort { $0.createdAt < $1.createdAt }
        }
        for path in buckets.lineCommentsByPath.keys {
            guard let lineNumbers = buckets.lineCommentsByPath[path]?.keys else {
                continue
            }
            for lineNumber in lineNumbers {
                buckets.lineCommentsByPath[path]?[lineNumber]?.sort { $0.createdAt < $1.createdAt }
            }
        }
        return buckets
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
