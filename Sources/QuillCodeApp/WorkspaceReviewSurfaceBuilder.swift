import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceReviewSurfaceBuilder: Sendable, Hashable {
    var toolCards: [ToolCardState]
    var events: [ThreadEvent]
    var thread: ChatThread? = nil
    var selectionOverride: WorkspaceReviewSelection? = nil
    var allowsTurnRevert: Bool = true
    var pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface?

    func surface() -> WorkspaceReviewSurface {
        let pullRequestThreads = latestPullRequestReviewThreadsCard
            .flatMap(pullRequestReviewThreads(from:)) ?? []

        if selectionOverride == .lastTurn, let thread {
            return WorkspaceLastTurnReviewSurfaceBuilder(
                thread: thread,
                allowsRevert: allowsTurnRevert,
                pullRequestThreads: pullRequestThreads,
                pullRequestReviewDraft: pullRequestReviewDraft
            ).surface()
        }

        guard let completedDiff = latestCompletedGitDiffResult else {
            return WorkspaceReviewSurface(
                title: pullRequestThreads.isEmpty ? "Review changes" : "Review threads",
                files: [],
                pullRequestThreads: pullRequestThreads,
                pullRequestReviewDraft: pullRequestReviewDraft
            )
        }

        var review = GitDiffReviewParser.parse(
            completedDiff.result.stdout,
            selection: completedDiff.selection
        )
        review.pullRequestThreads = pullRequestThreads
        review.pullRequestReviewDraft = pullRequestReviewDraft
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

    private struct CompletedGitDiff: Sendable, Hashable {
        var result: ToolResult
        var selection: WorkspaceReviewSelection
    }

    private var latestCompletedGitDiffResult: CompletedGitDiff? {
        guard let card = toolCards.reversed().first(where: { $0.title == ToolDefinition.gitDiff.name }),
              card.status == .done,
              let outputJSON = card.outputJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON),
              result.ok
        else {
            return nil
        }
        return CompletedGitDiff(
            result: result,
            selection: reviewSelection(from: card.inputJSON)
        )
    }

    private func reviewSelection(from inputJSON: String?) -> WorkspaceReviewSelection {
        guard let inputJSON,
              let arguments = try? ToolArguments(inputJSON)
        else {
            return .unstaged
        }
        if let commit = arguments.string("commit")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !commit.isEmpty {
            return .commit(commit)
        }
        if let baseBranch = arguments.string("baseBranch")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !baseBranch.isEmpty {
            return .branch(baseBranch)
        }
        return arguments.bool("staged") == true ? .staged : .unstaged
    }

    private var latestPullRequestReviewThreadsCard: ToolCardState? {
        toolCards.reversed().first { $0.title == ToolDefinition.gitPullRequestReviewThreads.name }
    }

    private func pullRequestReviewThreads(from card: ToolCardState) -> [WorkspacePullRequestReviewThreadSurface]? {
        guard card.status == .done,
              let outputJSON = card.outputJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON),
              result.ok
        else {
            return nil
        }
        return WorkspacePullRequestReviewThreadsParser.parse(
            result.stdout,
            selector: selector(from: card.inputJSON)
        )
    }

    private func selector(from inputJSON: String?) -> String? {
        guard let inputJSON,
              let arguments = try? ToolArguments(inputJSON)
        else {
            return nil
        }
        return arguments.string("selector")
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
