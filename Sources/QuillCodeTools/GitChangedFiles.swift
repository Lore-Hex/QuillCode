import Foundation

/// The set of workspace-relative paths that have uncommitted changes, parsed from the
/// porcelain body of `git status --short --branch` output. Shares the exact same stdout
/// the branch chip already consumes (`GitBranchStatus`), so surfacing changed files in
/// `@`-mention suggestions needs no extra git invocation.
public enum GitChangedFiles {
    /// Parses the changed-file paths from `git status --short --branch` output.
    ///
    /// Each non-header porcelain line has the form `XY␠path`, where `XY` is the two-character
    /// staged/unstaged status. Rename/copy lines carry `old -> new`; the post-arrow (current)
    /// path is kept. Quoted paths (git quotes names with special characters) are unquoted.
    /// The leading `## ` branch header — already parsed by `GitBranchStatus` — is skipped.
    public static func parse(statusShortBranchOutput: String) -> Set<String> {
        var paths: Set<String> = []
        for rawLine in statusShortBranchOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            // Skip the `## ` branch header and any line too short to carry a path.
            if line.hasPrefix("## ") { continue }
            guard line.count > 3 else { continue }

            var payload = String(line.dropFirst(3))
            // Renames/copies (status R/C) render as `old -> new`; keep the current path.
            // Only split for R/C so an ordinary path containing " -> " is never truncated.
            let status = line.prefix(2)
            if status.contains("R") || status.contains("C"),
               let arrow = payload.range(of: " -> ", options: .backwards) {
                payload = String(payload[arrow.upperBound...])
            }
            let path = cleanPath(payload)
            if !path.isEmpty { paths.insert(path) }
        }
        return paths
    }

    /// Strips the surrounding double quotes git adds around paths with special characters.
    /// (Porcelain short paths are not `a/`/`b/`-prefixed, unlike diff headers.)
    private static func cleanPath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("\"") { path.removeFirst() }
        if path.hasSuffix("\"") { path.removeLast() }
        return path
    }
}
