import Foundation
import QuillCodeCore

public struct GitPatchToolExecutor: Sendable {
    private let runner: GitProcessRunner

    public init(runner: GitProcessRunner = GitProcessRunner()) {
        self.runner = runner
    }

    public func stageHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        applyHunk(
            cwd: cwd,
            path: path,
            patch: patch,
            arguments: ["apply", "--cached", "--whitespace=nowarn"],
            successMessage: "Hunk staged.\n"
        )
    }

    public func restoreHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        applyHunk(
            cwd: cwd,
            path: path,
            patch: patch,
            arguments: ["apply", "--reverse", "--whitespace=nowarn"],
            successMessage: "Hunk restored.\n"
        )
    }

    public static func mismatchedPatchPath(in patch: String, expectedPath: String) -> String? {
        for line in patch.components(separatedBy: .newlines) {
            guard line.hasPrefix("--- ") || line.hasPrefix("+++ ") || line.hasPrefix("diff --git ") else {
                continue
            }
            for path in pathsInDiffMetadataLine(line) {
                guard path != "/dev/null" else { continue }
                let normalized = normalizedPatchPath(path)
                guard normalized == expectedPath else {
                    return normalized
                }
            }
        }
        return nil
    }

    private func applyHunk(
        cwd: URL,
        path: String,
        patch: String,
        arguments: [String],
        successMessage: String
    ) -> ToolResult {
        do {
            let relativePath = try GitInputValidator.safeRelativePath(path, cwd: cwd)
            let trimmedPatch = patch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPatch.isEmpty else {
                throw GitToolError.emptyPatch
            }
            if let mismatch = Self.mismatchedPatchPath(in: patch, expectedPath: relativePath) {
                throw GitToolError.patchPathMismatch(mismatch)
            }

            var normalizedPatch = patch
            if !normalizedPatch.hasSuffix("\n") {
                normalizedPatch.append("\n")
            }
            let patchURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("quillcode-hunk-\(UUID().uuidString).patch")
            do {
                try normalizedPatch.write(to: patchURL, atomically: true, encoding: .utf8)
            } catch {
                throw GitToolError.temporaryPatchFailed(String(describing: error))
            }
            defer { try? FileManager.default.removeItem(at: patchURL) }

            let check = runner.runGit(arguments + ["--check", patchURL.path], cwd: cwd, timeoutSeconds: 20)
            guard check.ok else { return check }
            let apply = runner.runGit(arguments + [patchURL.path], cwd: cwd, timeoutSeconds: 20)
            if apply.ok {
                return ToolResult(ok: true, stdout: successMessage, stderr: apply.stderr, exitCode: apply.exitCode)
            }
            return apply
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func pathsInDiffMetadataLine(_ line: String) -> [String] {
        if line.hasPrefix("diff --git ") {
            return pathsInDiffGitHeader(String(line.dropFirst("diff --git ".count)))
        }
        return line
            .dropFirst(4)
            .split(separator: "\t")
            .first
            .map { [String($0)] } ?? []
    }

    private static func pathsInDiffGitHeader(_ header: String) -> [String] {
        if header.hasPrefix("\"") {
            return quotedPaths(in: header)
        }
        guard let secondPathRange = header.range(of: " b/") else {
            return header.split(separator: " ").map(String.init)
        }
        let first = String(header[..<secondPathRange.lowerBound])
        let second = String(header[header.index(after: secondPathRange.lowerBound)...])
        return [first, second]
    }

    private static func quotedPaths(in header: String) -> [String] {
        var paths: [String] = []
        var current = ""
        var isInQuote = false
        var isEscaped = false

        for character in header {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                if isInQuote {
                    paths.append(current)
                    current = ""
                }
                isInQuote.toggle()
                continue
            }
            if isInQuote {
                current.append(character)
            }
        }
        return paths
    }

    private static func normalizedPatchPath(_ rawPath: String) -> String {
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
}
