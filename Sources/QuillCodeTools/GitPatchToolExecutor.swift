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

    public func unstageHunk(cwd: URL, path: String, patch: String) -> ToolResult {
        applyHunk(
            cwd: cwd,
            path: path,
            patch: patch,
            arguments: ["apply", "--cached", "--reverse", "--whitespace=nowarn"],
            successMessage: "Hunk unstaged.\n"
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

    /// Reverse-applies a whole turn's recorded `apply_patch` diffs to undo exactly that
    /// turn's file edits — never a restore-to-HEAD. `patches` are in chronological order;
    /// they are reverse-applied newest-first (so a create-then-edit on one file unwinds
    /// cleanly) via separate atomic `git apply --reverse` invocations. If any patch fails to
    /// apply (e.g. its lines changed since the turn ran), the whole revert is rolled back to
    /// the pre-revert state and the failure is returned — it never corrupts the tree or
    /// silently restores to HEAD.
    public func restoreTurnPatch(cwd: URL, patches: [String]) -> ToolResult {
        let ordered = patches.reversed()
            .map { $0.hasSuffix("\n") ? $0 : $0 + "\n" }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !ordered.isEmpty else {
            return ToolResult(ok: false, error: String(describing: GitToolError.emptyPatch))
        }

        // Validate every touched path stays inside the workspace, and snapshot those files
        // so a mid-sequence failure can be rolled back atomically.
        var touchedPaths: Set<String> = []
        do {
            for patch in ordered {
                for path in Self.referencedPaths(in: patch) {
                    _ = try GitInputValidator.safeRelativePath(path, cwd: cwd)
                    touchedPaths.insert(path)
                }
            }
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
        let snapshots = touchedPaths.map { FileSnapshot(cwd: cwd, path: $0) }

        for patch in ordered {
            let patchURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("quillcode-turn-\(UUID().uuidString).patch")
            do {
                try patch.write(to: patchURL, atomically: true, encoding: .utf8)
            } catch {
                return rollback(snapshots, after: ToolResult(ok: false, error: String(describing: GitToolError.temporaryPatchFailed(String(describing: error)))))
            }
            let result = reverseApplyWithTolerance(patchPath: patchURL.path, cwd: cwd)
            try? FileManager.default.removeItem(at: patchURL)
            guard result.ok else {
                return rollback(snapshots, after: result)
            }
        }
        return ToolResult(ok: true, stdout: "Reverted this turn's edits.\n")
    }

    /// The reverse tolerance ladder — mirrors `PatchToolExecutor`'s FORWARD ladder (strict, then
    /// `--recount`) so a turn patch the tolerant apply accepted via recounted headers can also be
    /// UN-applied. Without this, its revert fails strictly ("corrupt patch"), offering an undo that
    /// cannot undo. Strict-applied patches still reverse on the first rung, so this only engages for
    /// recounted matches. Only EXACTNESS-PRESERVING tolerance is used (no `--ignore-whitespace`): the
    /// reverse must still match the file byte-for-byte, so it fails (and rolls back) rather than
    /// silently discarding a user's later whitespace-only edit. Each rung is an atomic `git apply`.
    private static let reverseApplyLadders: [[String]] = [
        ["apply", "--reverse", "--whitespace=nowarn"],
        ["apply", "--reverse", "--whitespace=nowarn", "--recount"]
    ]

    private func reverseApplyWithTolerance(patchPath: String, cwd: URL) -> ToolResult {
        var strictFailure: ToolResult?
        for arguments in Self.reverseApplyLadders {
            let result = runner.runGit(arguments + [patchPath], cwd: cwd, timeoutSeconds: 30)
            if result.ok { return result }
            // The STRICT rung's diagnostics are the most precise, so keep them for total failure.
            if strictFailure == nil { strictFailure = result }
        }
        return strictFailure ?? ToolResult(ok: false, error: "Reverse apply failed.")
    }

    /// Rolls every touched file back to its pre-revert state after a failed patch, and
    /// returns the original failure — escalating to a distinct error if any file could NOT
    /// be restored, so the caller never reports a clean failure over a half-reverted tree.
    private func rollback(_ snapshots: [FileSnapshot], after failure: ToolResult) -> ToolResult {
        let unrestored = snapshots.compactMap { $0.restore() ? nil : $0.path }
        guard unrestored.isEmpty else {
            return ToolResult(ok: false, error: "Revert failed and could not fully roll back: \(unrestored.joined(separator: ", ")). Original error: \(failure.error ?? failure.stderr)")
        }
        return failure
    }

    /// Captures a file's pre-revert state (contents or absence) so a failed multi-patch
    /// revert can be rolled back without touching anything else.
    private struct FileSnapshot {
        let path: String
        let url: URL
        let contents: Data?

        init(cwd: URL, path: String) {
            self.path = path
            self.url = cwd.appendingPathComponent(path)
            self.contents = try? Data(contentsOf: url)
        }

        /// Restores the file to its captured state; returns `false` if it could not.
        func restore() -> Bool {
            guard let contents else {
                // The file did not exist pre-revert; remove it if a partial revert created it.
                guard FileManager.default.fileExists(atPath: url.path) else { return true }
                return (try? FileManager.default.removeItem(at: url)) != nil
            }
            // A reverse-apply may have deleted the file and pruned its now-empty parent dir,
            // so recreate the directory before writing the contents back.
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return (try? contents.write(to: url)) != nil
        }
    }

    /// Every non-`/dev/null` path referenced by the patch's diff metadata lines.
    static func referencedPaths(in patch: String) -> [String] {
        var paths: [String] = []
        for line in patch.components(separatedBy: .newlines) {
            for path in DiffHeaderPathParser.paths(in: line) where path != "/dev/null" {
                paths.append(normalizedPatchPath(path))
            }
        }
        return paths
    }

    public static func mismatchedPatchPath(in patch: String, expectedPath: String) -> String? {
        for line in patch.components(separatedBy: .newlines) {
            for path in DiffHeaderPathParser.paths(in: line) {
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

    private static func normalizedPatchPath(_ rawPath: String) -> String {
        DiffHeaderPathParser.strippingDiffPrefix(rawPath)
    }
}
