import Foundation

/// Deterministic derivation of the transcript's navigation anchors: the most recent turn that
/// produced an **error** (a failed tool run) and the most recent turn that produced a **diff**
/// (a file write / patch). These power the "jump to last error" and "jump to last diff"
/// affordances that every post-run investigation reaches for.
///
/// Everything is derived purely from the shared `TranscriptSurface` timeline, so the native
/// SwiftUI transcript, the HTML render, and the Playwright harness all agree on which item the
/// jump targets. No force-unwraps; a transcript with no error (or no diff) yields `nil`, and the
/// UI is expected to disable the corresponding affordance.
public struct TranscriptNavigationAnchors: Sendable, Equatable {
    /// The timeline-item id of the most recent error turn, or `nil` if the transcript has none.
    public var lastErrorAnchorID: String?
    /// The timeline-item id of the most recent diff turn, or `nil` if the transcript has none.
    public var lastDiffAnchorID: String?

    public init(lastErrorAnchorID: String? = nil, lastDiffAnchorID: String? = nil) {
        self.lastErrorAnchorID = lastErrorAnchorID
        self.lastDiffAnchorID = lastDiffAnchorID
    }

    public var hasError: Bool { lastErrorAnchorID != nil }
    public var hasDiff: Bool { lastDiffAnchorID != nil }

    public static func derive(from transcript: TranscriptSurface) -> TranscriptNavigationAnchors {
        derive(timeline: transcript.timelineItems)
    }

    public static func derive(timeline: [TranscriptTimelineItemSurface]) -> TranscriptNavigationAnchors {
        var lastError: String?
        var lastDiff: String?
        // Single forward pass; the last hit in timeline order is the most recent, so we simply
        // overwrite. (Reverse-find would be equivalent but this keeps one clear traversal.)
        for item in timeline {
            guard item.kind == .toolCard, let card = item.toolCard else { continue }
            if isErrorCard(card) {
                lastError = item.id
            }
            if isDiffCard(card) {
                lastDiff = item.id
            }
        }
        return TranscriptNavigationAnchors(lastErrorAnchorID: lastError, lastDiffAnchorID: lastDiff)
    }

    /// A tool card counts as an **error** when its run failed. `ToolCardStatus.failed` is set by
    /// the reducer for a nonzero-exit shell run, a tool that threw, etc. — the single source of
    /// truth for "this step went wrong", so we key off it rather than sniffing output text.
    static func isErrorCard(_ card: ToolCardState) -> Bool {
        card.status == .failed
    }

    /// A tool card counts as a **diff** when it wrote to the working tree: an `apply_patch`, a
    /// file write, or a commit. We detect this SOLELY from the tool *name* (`card.title`, which is
    /// the raw tool id like `host.apply_patch` / `host.file.write` / `host.git.commit`).
    ///
    /// We deliberately do NOT infer "diff" from file/path artifacts: read-only tools
    /// (`host.file.read` / `host.file.list` / `host.file.search`) all emit absolute-path
    /// artifacts, and `ToolArtifactValueClassifier` classifies an absolute path as `.file`. An
    /// artifact fallback therefore lights up "Last diff" in sessions that only read/listed/searched
    /// — and, since `derive()` keeps the *last* hit in timeline order, a `[apply_patch, file.read]`
    /// sequence would jump to the READ, defeating the "most recent file write/patch" contract. The
    /// tool name is the authoritative, deterministic signal that a run mutated the tree.
    static func isDiffCard(_ card: ToolCardState) -> Bool {
        isDiffProducingToolName(card.title)
    }

    /// Tool names whose successful run mutates files. Compared case-insensitively and tolerant of
    /// the `host.` prefix so both raw ids (`host.apply_patch`) and any de-prefixed display title
    /// (`apply_patch`) are recognized.
    static func isDiffProducingToolName(_ rawTitle: String) -> Bool {
        let name = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let stripped = name.hasPrefix("host.") ? String(name.dropFirst("host.".count)) : name
        return diffProducingToolNames.contains(stripped)
    }

    private static let diffProducingToolNames: Set<String> = [
        "apply_patch",
        "file.write",
        "git.commit",
        // Friendly display variants some surfaces show instead of the raw id.
        "edit",
        "write"
    ]
}
