import Foundation
import QuillCodeCore

/// Builds the durable, secret-redacted one-line record of a terminal agent-run failure. The failure
/// is appended to the run's OWN thread as a `.notice` so a background run that failed while the user
/// was on another thread still leaves a visible trace on reload: the transient `lastError` is
/// session-only (cleared on the next action, never persisted), and `finishAgentRun` drops the
/// failure entirely for a non-selected thread. The notice surfaces in the Activity event stream.
enum WorkspaceRunFailureNoticePlanner {
    /// Reuses the summary sanitizer so a persisted failure can never carry an API key or private key
    /// out of the raw error, and is collapsed to a single bounded line fit for the Activity row.
    static func noticeSummary(for error: any Error) -> String {
        let diagnostic = WorkspaceContextSummarySanitizer.diagnostic(from: String(describing: error))
        guard !diagnostic.isEmpty else { return "Run stopped after an error." }
        return "Run stopped after an error: \(diagnostic)"
    }
}
