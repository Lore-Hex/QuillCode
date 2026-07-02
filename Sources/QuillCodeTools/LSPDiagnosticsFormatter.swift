import Foundation

/// Renders project-wide diagnostics into the concise `file:line: message` block that gets appended to
/// a write result so the model sees its own breakage immediately. Errors are prioritized over
/// warnings, and the output is capped to at most `maxFiles` files (issue #863: ≤5) and a bounded
/// number of lines per file so a flood of diagnostics cannot blow up the model's context.
public enum LSPDiagnosticsFormatter {
    public static let maxFiles = 5
    static let maxPerFile = 10

    /// Formats diagnostics keyed by absolute path, relative to `workspaceRoot`. `editedPath` (if
    /// given) is listed first so the file just written is always shown even when other files also have
    /// issues. Returns `nil` when there are no errors or warnings to report.
    public static func format(
        diagnosticsByPath: [String: [LSPDiagnostic]],
        workspaceRoot: URL,
        editedPath: String? = nil
    ) -> String? {
        // Keep only errors and warnings; info/hints are not "did I break it" signal.
        var relevant: [(path: String, diagnostics: [LSPDiagnostic])] = []
        for (path, diagnostics) in diagnosticsByPath {
            let filtered = diagnostics.filter { $0.severity == .error || $0.severity == .warning }
            if !filtered.isEmpty {
                relevant.append((path, filtered))
            }
        }
        guard !relevant.isEmpty else { return nil }

        // Order: the edited file first, then files with errors before files with only warnings, then
        // by descending diagnostic count, then by path for determinism. Symlink-resolve so this matches
        // the canonical, symlink-resolved keys the LSP client stores diagnostics under.
        let editedResolved = editedPath.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        relevant.sort { lhs, rhs in
            let lhsEdited = lhs.path == editedResolved
            let rhsEdited = rhs.path == editedResolved
            if lhsEdited != rhsEdited { return lhsEdited }
            let lhsErrors = lhs.diagnostics.contains { $0.severity == .error }
            let rhsErrors = rhs.diagnostics.contains { $0.severity == .error }
            if lhsErrors != rhsErrors { return lhsErrors }
            if lhs.diagnostics.count != rhs.diagnostics.count { return lhs.diagnostics.count > rhs.diagnostics.count }
            return lhs.path < rhs.path
        }

        let shownFiles = relevant.prefix(maxFiles)
        var lines: [String] = []
        for entry in shownFiles {
            let relativePath = Self.relativePath(entry.path, workspaceRoot: workspaceRoot)
            // Within a file, errors before warnings, then by line.
            let ordered = entry.diagnostics.sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity.rawValue < rhs.severity.rawValue }
                return lhs.range.start.line < rhs.range.start.line
            }
            for diagnostic in ordered.prefix(maxPerFile) {
                let line = diagnostic.range.start.line + 1 // 1-based for the model
                let message = Self.singleLine(diagnostic.message)
                lines.append("\(relativePath):\(line): \(diagnostic.severity.label): \(message)")
            }
            if ordered.count > maxPerFile {
                lines.append("\(relativePath): (+\(ordered.count - maxPerFile) more)")
            }
        }

        var header = "LSP diagnostics:"
        if relevant.count > maxFiles {
            header += " (showing \(maxFiles) of \(relevant.count) files with issues)"
        }
        return ([header] + lines).joined(separator: "\n")
    }

    private static func relativePath(_ path: String, workspaceRoot: URL) -> String {
        let root = workspaceRoot.standardizedFileURL.path
        let rootPrefix = root.hasSuffix("/") ? root : "\(root)/"
        if path.hasPrefix(rootPrefix) {
            return String(path.dropFirst(rootPrefix.count))
        }
        return path
    }

    /// Collapses a multi-line diagnostic message to one line and bounds its length so a pathological
    /// message cannot dominate the block.
    private static func singleLine(_ message: String) -> String {
        let collapsed = message
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard collapsed.count > 300 else { return collapsed }
        return String(collapsed.prefix(300)) + "…"
    }
}
