import QuillCodeCore

/// Turns the review (git-diff) surface's per-file changes into a glanceable "what did this run do"
/// list for the Activity pane's `.changes` section.
///
/// This is the review-AFTER surface for unattended driving: you walk away, the agent works, and when
/// you check back you want the working-tree delta at a glance — which files it touched and how much —
/// without opening the full review pane. Files are ordered by churn (the biggest edits first, where
/// your attention should go), then by path for a stable order, and bounded so a sprawling run does not
/// flood the pane. Pure + testable; the caller feeds the already-computed review files.
enum WorkspaceActivityChangesSurfaceBuilder {
    /// The most files to list. A run that rewrites hundreds of files should still leave a readable
    /// summary — the count label ("N files") keeps the true total honest even when the list is capped.
    static let displayLimit = 12

    static func items(from files: [WorkspaceReviewFileSurface], limit: Int = displayLimit) -> [ActivityItemSurface] {
        files
            .sorted { lhs, rhs in
                let lhsChurn = lhs.insertions + lhs.deletions
                let rhsChurn = rhs.insertions + rhs.deletions
                if lhsChurn != rhsChurn { return lhsChurn > rhsChurn }
                return lhs.path < rhs.path
            }
            .prefix(max(0, limit))
            .map { file in
                ActivityItemSurface(
                    id: "change:\(file.path)",
                    title: file.path,
                    detail: file.changeLabel,
                    kind: "change",
                    statusLabel: file.isBinary ? "binary" : ""
                )
            }
    }
}
