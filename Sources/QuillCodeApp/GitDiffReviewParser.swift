import Foundation

enum GitDiffReviewParser {
    static func parse(_ diff: String) -> WorkspaceReviewSurface {
        var files: [WorkspaceReviewFileSurface] = []
        var current: DiffFileAccumulator?

        func finishCurrentFile() {
            guard let file = current else { return }
            files.append(file.surface)
            current = nil
        }

        for line in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                finishCurrentFile()
                current = DiffFileAccumulator(path: pathFromDiffHeader(line) ?? "Unknown file")
                continue
            }

            guard current != nil else { continue }

            if line.hasPrefix("+++ ") {
                if let path = pathFromNewFileHeader(line), path != "/dev/null" {
                    current?.path = path
                }
                continue
            }

            if line.hasPrefix("@@") {
                current?.hunks += 1
                continue
            }

            if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                current?.isBinary = true
                continue
            }

            if line.hasPrefix("+"), !line.hasPrefix("+++") {
                current?.insertions += 1
                continue
            }

            if line.hasPrefix("-"), !line.hasPrefix("---") {
                current?.deletions += 1
                continue
            }
        }

        finishCurrentFile()
        return WorkspaceReviewSurface(files: files)
    }

    private static func pathFromNewFileHeader(_ line: String) -> String? {
        let raw = String(line.dropFirst(4))
        guard raw != "/dev/null" else { return raw }
        return cleanGitPath(raw)
    }

    private static func pathFromDiffHeader(_ line: String) -> String? {
        if let range = line.range(of: " b/") {
            return cleanGitPath(String(line[range.upperBound...]))
        }
        if let range = line.range(of: "\"b/") {
            return cleanGitPath(String(line[range.upperBound...]))
        }
        guard let last = line.split(separator: " ").last else { return nil }
        return cleanGitPath(String(last))
    }

    private static func cleanGitPath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("\"") {
            path.removeFirst()
        }
        if path.hasSuffix("\"") {
            path.removeLast()
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path.removeFirst(2)
        }
        return path
    }

    private struct DiffFileAccumulator {
        var path: String
        var insertions = 0
        var deletions = 0
        var hunks = 0
        var isBinary = false

        var surface: WorkspaceReviewFileSurface {
            WorkspaceReviewFileSurface(
                path: path,
                insertions: insertions,
                deletions: deletions,
                hunks: hunks,
                isBinary: isBinary
            )
        }
    }
}
