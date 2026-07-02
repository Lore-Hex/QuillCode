import Foundation

/// Translates `git apply` stderr into a hunk-specific, model-actionable failure message.
///
/// `git apply --check` reports failures like `error: patch failed: <file>:<line>`; on its own that
/// leaves the model guessing which of its hunks was wrong. This names the failing hunk by parsing
/// the patch's `@@` headers, and adds "did you mean" siblings when the patch targets a missing
/// file. Returns nil when nothing in the stderr is recognized, so callers keep their generic
/// message for unknown failures.
public enum PatchFailureExplainer {
    public static func explain(stderr: String, patch: String, workspaceRoot: URL) -> String? {
        let files = parseFiles(in: patch)
        var explanations: [String] = []
        var explainedPaths = Set<String>()
        for line in stderr.components(separatedBy: .newlines) {
            guard line.hasPrefix("error: ") else { continue }
            let detail = String(line.dropFirst("error: ".count))
            if let failure = parsePatchFailed(detail) {
                explanations.append(hunkFailureMessage(
                    path: failure.path,
                    lineNumber: failure.line,
                    files: files
                ))
                explainedPaths.insert(failure.path)
            } else if let path = parseSuffixed(detail, suffix: ": No such file or directory") {
                explanations.append(missingTargetMessage(path: path, workspaceRoot: workspaceRoot))
                explainedPaths.insert(path)
            } else if let path = parseSuffixed(detail, suffix: ": already exists in working directory") {
                explanations.append("Patch creates a new file '\(path)' but that file already exists in the workspace.")
                explainedPaths.insert(path)
            } else if let lineNumber = parseMalformed(detail) {
                explanations.append(
                    "The patch itself is malformed at patch line \(lineNumber): check the @@ hunk headers and that unchanged context lines start with a space."
                )
            } else if let path = parseSuffixed(detail, suffix: ": patch does not apply"),
                      !explainedPaths.contains(path) {
                explanations.append("Patch for '\(path)' does not apply to the current file content.")
                explainedPaths.insert(path)
            }
        }
        return explanations.isEmpty ? nil : explanations.joined(separator: "\n")
    }

    struct PatchFileHunks {
        var path: String
        var hunks: [Hunk]

        struct Hunk {
            var oldStart: Int
            var header: String
        }
    }

    /// Collects each patched file's target path and `@@` hunk headers, in patch order.
    static func parseFiles(in patch: String) -> [PatchFileHunks] {
        var files: [PatchFileHunks] = []
        var pendingOldPath: String?
        for line in patch.components(separatedBy: .newlines) {
            if line.hasPrefix("--- ") {
                pendingOldPath = normalizedPath(String(line.dropFirst(4)))
            } else if line.hasPrefix("+++ ") {
                let newPath = normalizedPath(String(line.dropFirst(4)))
                files.append(PatchFileHunks(path: newPath ?? pendingOldPath ?? "?", hunks: []))
                pendingOldPath = nil
            } else if line.hasPrefix("@@ -"), !files.isEmpty, let oldStart = parseOldStart(line) {
                files[files.count - 1].hunks.append(.init(oldStart: oldStart, header: hunkHeader(line)))
            }
        }
        return files
    }

    private static func hunkFailureMessage(path: String, lineNumber: Int, files: [PatchFileHunks]) -> String {
        let advice = "Re-read the file and regenerate the patch from its current content."
        guard let file = files.first(where: { $0.path == path }),
              let index = failingHunkIndex(near: lineNumber, in: file.hunks)
        else {
            return "Patch hunk for '\(path)' failed: context mismatch at line \(lineNumber). \(advice)"
        }
        let hunk = file.hunks[index]
        return "Hunk \(index + 1) of \(file.hunks.count) for '\(path)' (\(hunk.header)) failed: the hunk's context does not match the file at line \(lineNumber). \(advice)"
    }

    /// git reports the failing hunk's old-file start line; prefer the exact header match, and fall
    /// back to the last hunk starting at or before the reported line (offsets can drift).
    private static func failingHunkIndex(near lineNumber: Int, in hunks: [PatchFileHunks.Hunk]) -> Int? {
        hunks.firstIndex { $0.oldStart == lineNumber }
            ?? hunks.lastIndex { $0.oldStart <= lineNumber }
    }

    private static func missingTargetMessage(path: String, workspaceRoot: URL) -> String {
        let base = "Patch target does not exist in the workspace: \(path)."
        let resolved = workspaceRoot.appendingPathComponent(path)
        guard let clause = FilePathSuggester.didYouMeanClause(requestedPath: path, resolvedURL: resolved) else {
            return base
        }
        return "\(base) \(clause)"
    }

    private static func normalizedPath(_ raw: String) -> String? {
        var path = raw.split(separator: "\t").first.map(String.init) ?? raw
        path = path.trimmingCharacters(in: .whitespaces)
        if path == "/dev/null" { return nil }
        if path.hasPrefix("a/") || path.hasPrefix("b/") { path.removeFirst(2) }
        return path.isEmpty ? nil : path
    }

    private static func parseOldStart(_ line: String) -> Int? {
        let digits = line.dropFirst("@@ -".count).prefix { $0.isNumber }
        return Int(digits)
    }

    private static func hunkHeader(_ line: String) -> String {
        // Trim any trailing section heading git appended after the closing "@@".
        guard let range = line.range(of: "@@", options: .backwards), range.lowerBound != line.startIndex else {
            return line
        }
        return String(line[..<range.upperBound])
    }

    private static func parsePatchFailed(_ detail: String) -> (path: String, line: Int)? {
        guard detail.hasPrefix("patch failed: ") else { return nil }
        let rest = detail.dropFirst("patch failed: ".count)
        guard let colon = rest.lastIndex(of: ":"),
              let line = Int(rest[rest.index(after: colon)...]),
              colon != rest.startIndex
        else {
            return nil
        }
        return (String(rest[..<colon]), line)
    }

    private static func parseSuffixed(_ detail: String, suffix: String) -> String? {
        guard detail.hasSuffix(suffix) else { return nil }
        let path = String(detail.dropLast(suffix.count))
        return path.isEmpty ? nil : path
    }

    private static func parseMalformed(_ detail: String) -> Int? {
        for prefix in ["corrupt patch at line ", "patch with only garbage at line "] where detail.hasPrefix(prefix) {
            return Int(detail.dropFirst(prefix.count))
        }
        return nil
    }
}
