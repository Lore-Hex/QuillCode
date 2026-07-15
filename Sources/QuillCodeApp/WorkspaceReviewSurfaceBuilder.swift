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

        let commentBuckets = Self.reviewCommentBuckets(from: events)
        guard let completedDiff = latestCompletedGitDiffResult else {
            let findingFiles = Self.findingOnlyFiles(from: commentBuckets.allComments)
            return WorkspaceReviewSurface(
                title: findingFiles.isEmpty && !pullRequestThreads.isEmpty ? "Review threads" : "Review changes",
                scopeNotice: latestGitDiffFailureMessage,
                files: findingFiles,
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
        var placedCommentIDs = Set<UUID>()
        review.files = review.files.map { file in
            var file = file
            file.comments = commentBuckets.fileCommentsByPath[file.path] ?? []
            placedCommentIDs.formUnion(file.comments.map(\.id))
            file.hunkItems = file.hunkItems.map { hunk in
                var hunk = hunk
                hunk.lines = hunk.lines.map { line in
                    var line = line
                    if let displayLineNumber = line.displayLineNumber {
                        line.comments = commentBuckets.lineCommentsByPath[file.path]?[displayLineNumber]?.filter { comment in
                            !placedCommentIDs.contains(comment.id)
                                && (comment.lineKind == nil || comment.lineKind == line.kind)
                                && !(comment.source == .codeReview
                                    && comment.lineKind == nil
                                    && line.kind == .deletion)
                        } ?? []
                        placedCommentIDs.formUnion(line.comments.map(\.id))
                    }
                    return line
                }
                return hunk
            }
            return file
        }
        let unplacedFindings = commentBuckets.allComments.filter {
            $0.source == .codeReview && !placedCommentIDs.contains($0.id)
        }
        for finding in unplacedFindings {
            if let index = review.files.firstIndex(where: { $0.path == finding.path }) {
                review.files[index].comments.append(finding)
            } else {
                review.files.append(Self.findingOnlyFile(path: finding.path, comments: [finding]))
            }
        }
        return WorkspaceReviewSurface(
            isPresented: review.isPresented,
            title: review.title,
            activeScope: review.activeScope,
            scopeReference: review.scopeReference,
            scopeNotice: review.scopeNotice,
            lastTurnMessageID: review.lastTurnMessageID,
            files: review.files,
            pullRequestThreads: review.pullRequestThreads,
            pullRequestReviewDraft: review.pullRequestReviewDraft
        )
    }

    private struct CompletedGitDiff: Sendable, Hashable {
        var result: ToolResult
        var selection: WorkspaceReviewSelection
    }

    private var latestGitDiffCard: ToolCardState? {
        toolCards.reversed().first { $0.title == ToolDefinition.gitDiff.name }
    }

    private var latestCompletedGitDiffResult: CompletedGitDiff? {
        guard let card = latestGitDiffCard,
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

    private var latestGitDiffFailureMessage: String? {
        guard let card = latestGitDiffCard,
              card.status == .failed || card.status == .done
        else {
            return nil
        }
        guard let outputJSON = card.outputJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON)
        else {
            return card.status == .failed ? "Couldn't load this review." : nil
        }
        guard !result.ok else { return nil }
        let detail = [result.error, result.stderr]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return detail.map { "Couldn't load this review: \($0)" }
            ?? "Couldn't load this review."
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
        var allComments: [WorkspaceReviewCommentSurface] = []
    }

    private static func reviewCommentBuckets(from events: [ThreadEvent]) -> ReviewCommentBuckets {
        var buckets = ReviewCommentBuckets()
        for event in events where event.kind == .reviewComment {
            guard let comment = decode(WorkspaceReviewCommentState.self, event.payloadJSON) else {
                continue
            }
            let surface = WorkspaceReviewCommentSurface(comment: comment)
            buckets.allComments.append(surface)
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

    private static func findingOnlyFiles(
        from comments: [WorkspaceReviewCommentSurface]
    ) -> [WorkspaceReviewFileSurface] {
        Dictionary(grouping: comments.filter { $0.source == .codeReview }, by: \.path)
            .map { path, comments in findingOnlyFile(path: path, comments: comments) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func findingOnlyFile(
        path: String,
        comments: [WorkspaceReviewCommentSurface]
    ) -> WorkspaceReviewFileSurface {
        WorkspaceReviewFileSurface(
            path: path,
            insertions: 0,
            deletions: 0,
            hunks: 0,
            isFindingOnly: true,
            comments: comments.sorted { $0.createdAt < $1.createdAt }
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
