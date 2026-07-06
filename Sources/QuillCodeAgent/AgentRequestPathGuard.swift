import Foundation

/// The shared first-pass safety guard for a workspace-relative path extracted from a natural-language
/// request (the mock / simulated tool-call path). It rejects the paths a workspace-relative reference
/// must never be: empty, absolute (`/` or `~`), a URL (`http`/`https`/`file`), or containing a `..`
/// traversal segment. Each parser layers its OWN pre-trimming and extra validation (punctuation
/// stripping, stopword lists, file-path shape) around this common core.
///
/// This is a convenience filter, not the security boundary — the executors enforce containment via
/// `WorkspaceBoundary.isWithin`. Centralizing the core keeps the five parsers' guards from drifting.
enum AgentRequestPathGuard {
    static func isSafeWorkspaceRelativePath(_ trimmed: String) -> Bool {
        let lower = trimmed.lowercased()
        return !trimmed.isEmpty
            && !trimmed.hasPrefix("/")
            && !trimmed.hasPrefix("~")
            && !lower.hasPrefix("http://")
            && !lower.hasPrefix("https://")
            && !lower.hasPrefix("file://")
            && !trimmed.split(separator: "/").contains("..")
    }
}
