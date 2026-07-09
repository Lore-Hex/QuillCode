import Foundation

enum GitDiffReviewParser {
    static func parse(_ diff: String) -> WorkspaceReviewSurface {
        var files: [WorkspaceReviewFileSurface] = []
        var current: DiffFileAccumulator?

        func finishCurrentFile() {
            guard var file = current else { return }
            file.finishHunk()
            files.append(file.surface)
            current = nil
        }

        for line in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                finishCurrentFile()
                current = DiffFileAccumulator(
                    path: pathFromDiffHeader(line) ?? "Unknown file",
                    diffHeader: line
                )
                continue
            }

            guard current != nil else { continue }

            if line.hasPrefix("--- ") {
                current?.oldHeader = line
                continue
            }

            if line.hasPrefix("+++ ") {
                if let path = pathFromNewFileHeader(line), path != "/dev/null" {
                    current?.path = path
                } else if line == "+++ /dev/null" {
                    current?.isDeleted = true
                }
                current?.newHeader = line
                continue
            }

            if line.hasPrefix("@@") {
                current?.startHunk(line)
                continue
            }

            if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                current?.isBinary = true
                continue
            }

            if current?.isInHunk == true {
                current?.appendHunkLine(line)
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
        var diffHeader: String
        var oldHeader: String?
        var newHeader: String?
        var insertions = 0
        var deletions = 0
        var hunks = 0
        var isBinary = false
        var isDeleted = false
        var hunkItems: [WorkspaceReviewHunkSurface] = []
        var currentHunk: DiffHunkAccumulator?

        var isInHunk: Bool {
            currentHunk != nil
        }

        mutating func startHunk(_ header: String) {
            finishHunk()
            hunks += 1
            currentHunk = DiffHunkAccumulator(
                id: "\(path):hunk-\(hunks)",
                path: path,
                diffHeader: diffHeader,
                oldHeader: oldHeader ?? "--- a/\(path)",
                newHeader: newHeader ?? "+++ b/\(path)",
                header: header
            )
        }

        mutating func appendHunkLine(_ line: String) {
            let kind = currentHunk?.appendDiffLine(line)
            if kind == .insertion {
                insertions += 1
                currentHunk?.insertions += 1
            } else if kind == .deletion {
                deletions += 1
                currentHunk?.deletions += 1
            }
        }

        mutating func finishHunk() {
            guard let currentHunk else { return }
            hunkItems.append(currentHunk.surface)
            self.currentHunk = nil
        }

        var surface: WorkspaceReviewFileSurface {
            WorkspaceReviewFileSurface(
                path: path,
                insertions: insertions,
                deletions: deletions,
                hunks: hunks,
                isBinary: isBinary,
                isDeleted: isDeleted,
                hunkItems: hunkItems
            )
        }
    }

    private struct DiffHunkAccumulator {
        var id: String
        var path: String
        var diffHeader: String
        var oldHeader: String
        var newHeader: String
        var header: String
        var insertions = 0
        var deletions = 0
        var diffLines: [String] = []
        var reviewLines: [WorkspaceReviewLineSurface] = []
        var oldLineNumber: Int
        var newLineNumber: Int

        init(
            id: String,
            path: String,
            diffHeader: String,
            oldHeader: String,
            newHeader: String,
            header: String
        ) {
            let startingLines = Self.startingLines(from: header)
            self.id = id
            self.path = path
            self.diffHeader = diffHeader
            self.oldHeader = oldHeader
            self.newHeader = newHeader
            self.header = header
            self.oldLineNumber = startingLines.old
            self.newLineNumber = startingLines.new
        }

        mutating func appendDiffLine(_ line: String) -> WorkspaceReviewLineKind? {
            diffLines.append(line)
            guard let first = line.first,
                  first == " " || first == "+" || first == "-"
            else {
                return nil
            }

            let kind: WorkspaceReviewLineKind
            let oldNumber: Int?
            let newNumber: Int?
            switch first {
            case "+":
                kind = .insertion
                oldNumber = nil
                newNumber = newLineNumber
                newLineNumber += 1
            case "-":
                kind = .deletion
                oldNumber = oldLineNumber
                newNumber = nil
                oldLineNumber += 1
            default:
                kind = .context
                oldNumber = oldLineNumber
                newNumber = newLineNumber
                oldLineNumber += 1
                newLineNumber += 1
            }

            reviewLines.append(WorkspaceReviewLineSurface(
                id: "\(id):line-\(reviewLines.count + 1)",
                path: path,
                hunkID: id,
                oldLineNumber: oldNumber,
                newLineNumber: newNumber,
                kind: kind,
                content: String(line.dropFirst())
            ))
            return kind
        }

        var surface: WorkspaceReviewHunkSurface {
            let patch = ([diffHeader, oldHeader, newHeader, header] + diffLines).joined(separator: "\n") + "\n"
            return WorkspaceReviewHunkSurface(
                id: id,
                path: path,
                header: header,
                insertions: insertions,
                deletions: deletions,
                patch: patch,
                lines: reviewLines
            )
        }

        private static func startingLines(from header: String) -> (old: Int, new: Int) {
            let parts = header.split(separator: " ")
            let oldToken = parts.first { $0.hasPrefix("-") }
            let newToken = parts.first { $0.hasPrefix("+") }
            return (
                old: lineStart(from: oldToken) ?? 1,
                new: lineStart(from: newToken) ?? 1
            )
        }

        private static func lineStart(from token: Substring?) -> Int? {
            guard let token else { return nil }
            let trimmed = token.dropFirst().split(separator: ",", maxSplits: 1).first
            return trimmed.flatMap { Int($0) }
        }
    }
}
