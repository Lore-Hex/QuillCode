import Foundation
import QuillCodeCore

/// Builds Review's "Last turn" comparison from the exact `apply_patch` calls recorded for the
/// newest user turn. This is durable provenance: it does not confuse an older edit-bearing turn
/// with an empty latest turn, and it does not depend on the repository's current dirty state.
struct WorkspaceLastTurnReviewSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread
    var allowsRevert: Bool = true
    var pullRequestThreads: [WorkspacePullRequestReviewThreadSurface] = []
    var pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface?

    func surface() -> WorkspaceReviewSurface {
        guard let plan = WorkspaceTurnRevertPlanner.latestTurnPlan(in: thread) else {
            return WorkspaceReviewSurface(
                activeScope: .lastTurn,
                files: [],
                pullRequestThreads: pullRequestThreads,
                pullRequestReviewDraft: pullRequestReviewDraft
            )
        }

        return WorkspaceReviewSurface(
            activeScope: .lastTurn,
            scopeNotice: plan.hasNonApplyPatchEdits ? Self.partialProvenanceNotice : nil,
            lastTurnMessageID: allowsRevert ? plan.turnMessageID : nil,
            files: coalescedFiles(from: plan.patches),
            pullRequestThreads: pullRequestThreads,
            pullRequestReviewDraft: pullRequestReviewDraft
        )
    }

    /// Multiple patch calls may touch the same file. Review presents one stable file row and keeps
    /// each call's hunks in chronological order. IDs are namespaced by call index so overlapping
    /// hunks from successive patches remain distinct in SwiftUI and HTML renderers.
    private func coalescedFiles(from patches: [String]) -> [WorkspaceReviewFileSurface] {
        var files: [WorkspaceReviewFileSurface] = []
        var indexByPath: [String: Int] = [:]

        for (patchIndex, patch) in patches.enumerated() {
            let parsed = GitDiffReviewParser.parse(patch, selection: .lastTurn)
            for parsedFile in parsed.files {
                let file = namespaced(parsedFile, patchIndex: patchIndex)
                if let existingIndex = indexByPath[file.path] {
                    files[existingIndex].insertions += file.insertions
                    files[existingIndex].deletions += file.deletions
                    files[existingIndex].hunks += file.hunks
                    // The latest patch owns the final readability state. A file can be deleted
                    // and recreated (or vice versa) within one turn; OR-ing these flags would
                    // incorrectly leave the coalesced row unreadable.
                    files[existingIndex].isBinary = file.isBinary
                    files[existingIndex].isDeleted = file.isDeleted
                    files[existingIndex].hunkItems.append(contentsOf: file.hunkItems)
                } else {
                    indexByPath[file.path] = files.count
                    files.append(file)
                }
            }
        }
        return files
    }

    private func namespaced(
        _ file: WorkspaceReviewFileSurface,
        patchIndex: Int
    ) -> WorkspaceReviewFileSurface {
        var file = file
        file.hunkItems = file.hunkItems.map { hunk in
            var hunk = hunk
            let hunkID = "turn-\(patchIndex)-\(hunk.id)"
            hunk.id = hunkID
            hunk.lines = hunk.lines.map { line in
                var line = line
                line.id = "turn-\(patchIndex)-\(line.id)"
                line.hunkID = hunkID
                return line
            }
            return hunk
        }
        return file
    }

    static let partialProvenanceNotice =
        "This turn also used mutating tools outside apply_patch; those changes are not shown here."
}
