import Foundation
import QuillCodeCore

public enum PatchToolError: Error, CustomStringConvertible {
    case unsafePath(String)
    case emptyPatch
    case temporaryFileFailed(String)

    public var description: String {
        switch self {
        case .unsafePath(let path):
            return "Patch touches an unsafe path outside the workspace: \(path)"
        case .emptyPatch:
            return "Patch is empty."
        case .temporaryFileFailed(let message):
            return "Failed to prepare temporary patch file: \(message)"
        }
    }
}

public struct PatchToolExecutor: Sendable {
    public var workspaceRoot: URL
    /// When set, `apply` refuses to patch an existing file the session never read and serializes
    /// concurrent edits to the patched files. When nil (the default), patching is unguarded —
    /// direct programmatic use such as test fixtures. `ToolRouter` always injects a guard.
    public var editGuard: FileEditSessionGuard?
    private let shell: ShellToolExecutor

    public init(
        workspaceRoot: URL,
        shell: ShellToolExecutor = ShellToolExecutor(),
        editGuard: FileEditSessionGuard? = nil
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.shell = shell
        self.editGuard = editGuard
    }

    public func apply(unifiedDiff patch: String) -> ToolResult {
        let trimmed = patch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolResult(ok: false, error: String(describing: PatchToolError.emptyPatch))
        }
        if let unsafe = Self.unsafePath(in: patch, workspaceRoot: workspaceRoot) {
            return ToolResult(ok: false, error: String(describing: PatchToolError.unsafePath(unsafe)))
        }

        var normalizedPatch = patch
        if !normalizedPatch.hasSuffix("\n") {
            normalizedPatch.append("\n")
        }

        guard let editGuard else {
            return performApply(normalizedPatch)
        }
        let targets = Self.targetPaths(in: patch)
            .map { (path: $0, url: workspaceRoot.appendingPathComponent($0).standardizedFileURL) }
        // The read-set check, git apply, and read-set update happen under the per-file locks so
        // a concurrent edit to any of the patched files cannot interleave with them.
        return editGuard.withExclusiveAccess(to: targets.map(\.url)) {
            for target in targets
            where FileManager.default.fileExists(atPath: target.url.path) && !editGuard.hasRead(target.url) {
                return ToolResult(
                    ok: false,
                    error: String(describing: FileEditGuardError.patchWithoutRead(target.path))
                )
            }
            let result = performApply(normalizedPatch)
            if result.ok {
                // The session knows each surviving file's content now: old content it read (or
                // /dev/null for a created file) plus the delta it just applied.
                for target in targets where FileManager.default.fileExists(atPath: target.url.path) {
                    editGuard.markRead(target.url)
                }
            }
            return result
        }
    }

    private func performApply(_ normalizedPatch: String) -> ToolResult {
        let patchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(UUID().uuidString).patch")
        do {
            try normalizedPatch.write(to: patchURL, atomically: true, encoding: .utf8)
        } catch {
            return ToolResult(ok: false, error: String(describing: PatchToolError.temporaryFileFailed(String(describing: error))))
        }
        defer { try? FileManager.default.removeItem(at: patchURL) }

        let quoted = shellQuote(patchURL.path)
        let check = shell.run(.init(command: "git apply --check \(quoted)", cwd: workspaceRoot, timeoutSeconds: 20))
        guard check.ok else {
            return ToolResult(
                ok: false,
                stdout: check.stdout,
                stderr: check.stderr,
                exitCode: check.exitCode,
                error: check.error ?? "Patch check failed."
            )
        }
        let apply = shell.run(.init(command: "git apply \(quoted)", cwd: workspaceRoot, timeoutSeconds: 20))
        if apply.ok {
            return ToolResult(
                ok: true,
                stdout: "Patch applied.\n",
                stderr: apply.stderr,
                exitCode: apply.exitCode
            )
        }
        return apply
    }

    public static func unsafePath(in patch: String) -> String? {
        unsafePath(in: patch, workspaceRoot: nil)
    }

    /// The workspace-relative file paths a unified diff touches (old and new sides, rename/copy
    /// headers, `/dev/null` excluded), deduplicated in order of first appearance. Handles git's
    /// C-style quoted paths (`core.quotepath`) and filenames with spaces.
    public static func targetPaths(in patch: String) -> [String] {
        DiffHeaderPathParser.targetPaths(in: patch)
    }

    /// Scans a unified diff for any target path that escapes the workspace. When `workspaceRoot` is
    /// provided (the local path) the check is symlink-resolved as well as lexical; for a remote patch
    /// (`workspaceRoot == nil`) only the lexical check runs locally — the remote `git apply` enforces
    /// its own boundary on the remote filesystem.
    ///
    /// This catches escapes through a *pre-existing* symlink. A patch that *creates* a symlink and then
    /// writes through it within the same diff cannot be caught here (the symlink does not exist at
    /// validate time), but `git apply` itself refuses with "affected file … is beyond a symbolic link",
    /// so that case is backstopped at apply time.
    public static func unsafePath(in patch: String, workspaceRoot: URL?) -> String? {
        for line in patch.components(separatedBy: .newlines) {
            for path in pathsInDiffMetadataLine(line) where isUnsafeDiffPath(path, workspaceRoot: workspaceRoot) {
                return path
            }
        }
        return nil
    }

    private static func pathsInDiffMetadataLine(_ line: String) -> [String] {
        DiffHeaderPathParser.paths(in: line)
    }

    private static func isUnsafeDiffPath(_ rawPath: String, workspaceRoot: URL?) -> Bool {
        if rawPath == "/dev/null" { return false }
        var path = rawPath
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path.removeFirst(2)
        }
        // Lexical rejects (fast path, and the only check available for a remote patch).
        if path.hasPrefix("/") || path == ".." || path.hasPrefix("../") || path.contains("/../") {
            return true
        }
        // Local patch: also reject a target that escapes via a symlink inside the workspace, matching
        // FileToolExecutor / GitInputValidator. (Remote patches rely on the remote git apply.)
        if let workspaceRoot {
            return !WorkspaceBoundary.isWithin(workspaceRoot.appendingPathComponent(path), root: workspaceRoot)
        }
        return false
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public extension ToolDefinition {
    static let applyPatch = ToolDefinition(
        name: "host.apply_patch",
        description: "Apply a unified diff patch inside the project workspace.",
        parametersJSON: #"{"type":"object","properties":{"patch":{"type":"string"}},"required":["patch"]}"#,
        host: .local,
        risk: .append
    )
}
