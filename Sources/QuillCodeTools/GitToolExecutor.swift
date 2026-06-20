import Foundation
import QuillCodeCore

public enum GitToolError: Error, CustomStringConvertible {
    case emptyPath
    case emptyPatch
    case emptyCommitMessage
    case outsideWorkspace(String)
    case patchPathMismatch(String)
    case temporaryPatchFailed(String)

    public var description: String {
        switch self {
        case .emptyPath:
            return "Git path is required."
        case .emptyPatch:
            return "Git patch is empty."
        case .emptyCommitMessage:
            return "Git commit message is required."
        case .outsideWorkspace(let path):
            return "Git path is outside the workspace: \(path)"
        case .patchPathMismatch(let path):
            return "Git patch touches a different path than requested: \(path)"
        case .temporaryPatchFailed(let message):
            return "Failed to prepare git patch: \(message)"
        }
    }
}

public struct GitToolExecutor: Sendable {
    private let shell: ShellToolExecutor

    public init(shell: ShellToolExecutor = ShellToolExecutor()) {
        self.shell = shell
    }

    public func status(cwd: URL) -> ToolResult {
        shell.run(.init(command: "git status --short --branch", cwd: cwd, timeoutSeconds: 15))
    }

    public func diff(cwd: URL, staged: Bool = false) -> ToolResult {
        shell.run(.init(command: staged ? "git diff --staged" : "git diff", cwd: cwd, timeoutSeconds: 20))
    }

    public func stage(cwd: URL, path: String) -> ToolResult {
        do {
            return runGit(["add", "--", try safeRelativePath(path, cwd: cwd)], cwd: cwd, timeoutSeconds: 20)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func restore(cwd: URL, path: String, staged: Bool = false) -> ToolResult {
        do {
            var arguments = ["restore"]
            if staged {
                arguments.append("--staged")
            }
            arguments += ["--", try safeRelativePath(path, cwd: cwd)]
            return runGit(arguments, cwd: cwd, timeoutSeconds: 20)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func stageHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        applyHunk(cwd: cwd, path: path, patch: patch, arguments: ["apply", "--cached", "--whitespace=nowarn"], successMessage: "Hunk staged.\n")
    }

    public func restoreHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        applyHunk(cwd: cwd, path: path, patch: patch, arguments: ["apply", "--reverse", "--whitespace=nowarn"], successMessage: "Hunk restored.\n")
    }

    public func commit(cwd: URL, message: String) -> ToolResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolResult(ok: false, error: String(describing: GitToolError.emptyCommitMessage))
        }
        return runGit(["commit", "-m", trimmed], cwd: cwd, timeoutSeconds: 30)
    }

    private func safeRelativePath(_ path: String, cwd: URL) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitToolError.emptyPath
        }

        let root = cwd.standardizedFileURL
        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : root.appendingPathComponent(trimmed)
        let standardized = candidate.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard standardized.path == root.path || standardized.path.hasPrefix(rootPath) else {
            throw GitToolError.outsideWorkspace(path)
        }
        guard standardized.path != root.path else {
            return "."
        }
        return String(standardized.path.dropFirst(rootPath.count))
    }

    private func applyHunk(
        cwd: URL,
        path: String,
        patch: String,
        arguments: [String],
        successMessage: String
    ) -> ToolResult {
        do {
            let relativePath = try safeRelativePath(path, cwd: cwd)
            let trimmedPatch = patch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPatch.isEmpty else {
                throw GitToolError.emptyPatch
            }
            if let mismatch = mismatchedPatchPath(in: patch, expectedPath: relativePath) {
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

            let check = runGit(arguments + ["--check", patchURL.path], cwd: cwd, timeoutSeconds: 20)
            guard check.ok else { return check }
            let apply = runGit(arguments + [patchURL.path], cwd: cwd, timeoutSeconds: 20)
            if apply.ok {
                return ToolResult(ok: true, stdout: successMessage, stderr: apply.stderr, exitCode: apply.exitCode)
            }
            return apply
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func mismatchedPatchPath(in patch: String, expectedPath: String) -> String? {
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

    private func pathsInDiffMetadataLine(_ line: String) -> [String] {
        if line.hasPrefix("diff --git ") {
            return pathsInDiffGitHeader(String(line.dropFirst("diff --git ".count)))
        }
        return line
            .dropFirst(4)
            .split(separator: "\t")
            .first
            .map { [String($0)] } ?? []
    }

    private func pathsInDiffGitHeader(_ header: String) -> [String] {
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

    private func quotedPaths(in header: String) -> [String] {
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

    private func normalizedPatchPath(_ rawPath: String) -> String {
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

    private func runGit(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ToolResult(ok: false, error: "Failed to start git: \(error)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            return ToolResult(ok: false, error: "Git command timed out after \(Int(timeoutSeconds))s.")
        }

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let ok = process.terminationStatus == 0
        return ToolResult(
            ok: ok,
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus,
            error: ok ? nil : "Git command failed with exit code \(process.terminationStatus)."
        )
    }
}

public extension ToolDefinition {
    static let gitStatus = ToolDefinition(
        name: "host.git.status",
        description: "Show git status for the project.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .local,
        risk: .read
    )

    static let gitDiff = ToolDefinition(
        name: "host.git.diff",
        description: "Show git diff for the project.",
        parametersJSON: #"{"type":"object","properties":{"staged":{"type":"boolean"}}}"#,
        host: .local,
        risk: .read
    )

    static let gitStage = ToolDefinition(
        name: "host.git.stage",
        description: "Stage one file path inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .append
    )

    static let gitRestore = ToolDefinition(
        name: "host.git.restore",
        description: "Restore one file path inside the project from git.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"staged":{"type":"boolean"}},"required":["path"]}"#,
        host: .local,
        risk: .destructive
    )

    static let gitStageHunk = ToolDefinition(
        name: "host.git.stage_hunk",
        description: "Stage one selected git diff hunk inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"patch":{"type":"string"}},"required":["path","patch"]}"#,
        host: .local,
        risk: .append
    )

    static let gitRestoreHunk = ToolDefinition(
        name: "host.git.restore_hunk",
        description: "Restore one selected git diff hunk inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"patch":{"type":"string"}},"required":["path","patch"]}"#,
        host: .local,
        risk: .destructive
    )

    static let gitCommit = ToolDefinition(
        name: "host.git.commit",
        description: "Create a git commit from already staged project changes.",
        parametersJSON: #"{"type":"object","properties":{"message":{"type":"string"}},"required":["message"]}"#,
        host: .local,
        risk: .append
    )
}
