import Foundation
import QuillCodeCore

struct GitWorktreeHandoffExecutor: Sendable {
    private let runner: GitProcessRunner
    private let limits: ManagedWorktreeTransferLimits
    private let preflight: GitWorktreeHandoffPreflight
    private let historyTransfer: GitWorktreeHandoffHistoryTransfer
    private let snapshotApplier: ManagedWorktreeSnapshotApplier

    init(
        runner: GitProcessRunner,
        limits: ManagedWorktreeTransferLimits = ManagedWorktreeTransferLimits()
    ) {
        self.runner = runner
        self.limits = limits
        self.preflight = GitWorktreeHandoffPreflight(runner: runner)
        self.historyTransfer = GitWorktreeHandoffHistoryTransfer(runner: runner)
        self.snapshotApplier = ManagedWorktreeSnapshotApplier(runner: runner)
    }

    func handoff(sourceRoot: URL, destinationPath: String) -> ToolResult {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-worktree-handoff-\(UUID().uuidString)")
        do {
            let plan = try preflight.plan(
                sourceRoot: sourceRoot,
                destinationPath: destinationPath
            )
            let destinationRoot = plan.destinationRoot
            let initialSnapshotRoot = temporaryRoot.appendingPathComponent("initial")
            try FileManager.default.createDirectory(at: initialSnapshotRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryRoot) }
            let snapshot = try ManagedWorktreeTransferSnapshot.capture(
                sourceRoot: sourceRoot,
                temporaryDirectory: initialSnapshotRoot,
                runner: runner,
                localFilePolicy: .handoff,
                limits: limits
            )
            guard try preflight.revision(sourceRoot) == plan.sourceCommit else {
                throw GitWorktreeHandoffError.checkoutChanged("source")
            }

            let destinationWasClean = try preflight.isClean(destinationRoot)
            if plan.historyTransition.requiresAdvance, !destinationWasClean {
                throw GitWorktreeHandoffError.destinationNotCleanForHistory
            }
            var destinationAlreadyMatched = false
            if !destinationWasClean {
                let destinationSnapshotRoot = temporaryRoot.appendingPathComponent("destination")
                try FileManager.default.createDirectory(
                    at: destinationSnapshotRoot,
                    withIntermediateDirectories: true
                )
                let destinationSnapshot = try ManagedWorktreeTransferSnapshot.capture(
                    sourceRoot: destinationRoot,
                    temporaryDirectory: destinationSnapshotRoot,
                    runner: runner,
                    localFilePolicy: .handoff,
                    limits: limits
                )
                guard try snapshot.hasSameContent(as: destinationSnapshot) else {
                    throw GitWorktreeHandoffError.destinationNotClean
                }
                destinationAlreadyMatched = true
            }

            guard try preflight.revision(sourceRoot) == plan.sourceCommit else {
                throw GitWorktreeHandoffError.checkoutChanged("source")
            }
            guard try preflight.revision(destinationRoot) == plan.destinationCommit else {
                throw GitWorktreeHandoffError.checkoutChanged("destination")
            }

            do {
                try historyTransfer.apply(plan.historyTransition, at: destinationRoot)
                let copied = destinationAlreadyMatched
                    ? 0
                    : try snapshotApplier.apply(snapshot, to: destinationRoot)
                let verificationRoot = temporaryRoot.appendingPathComponent("verification")
                try FileManager.default.createDirectory(at: verificationRoot, withIntermediateDirectories: true)
                let verification = try ManagedWorktreeTransferSnapshot.capture(
                    sourceRoot: sourceRoot,
                    temporaryDirectory: verificationRoot,
                    runner: runner,
                    localFilePolicy: .handoff,
                    limits: limits
                )
                guard try snapshot.hasSameContent(as: verification) else {
                    throw GitWorktreeHandoffError.sourceChanged
                }
                guard try preflight.revision(sourceRoot) == plan.sourceCommit else {
                    throw GitWorktreeHandoffError.sourceChanged
                }

                let destinationVerificationRoot = temporaryRoot.appendingPathComponent("destination-verification")
                try FileManager.default.createDirectory(
                    at: destinationVerificationRoot,
                    withIntermediateDirectories: true
                )
                let destinationVerification = try ManagedWorktreeTransferSnapshot.capture(
                    sourceRoot: destinationRoot,
                    temporaryDirectory: destinationVerificationRoot,
                    runner: runner,
                    localFilePolicy: .handoff,
                    limits: limits
                )
                guard try snapshot.hasSameContent(as: destinationVerification),
                      try preflight.revision(destinationRoot) == plan.sourceCommit else {
                    throw GitWorktreeHandoffError.checkoutChanged("destination")
                }

                let cleanup = cleanSource(snapshot, sourceRoot: sourceRoot)
                let warning = cleanup.ok
                    ? ""
                    : "\nWarning: the destination is complete, but source cleanup was incomplete. "
                        + "Some task changes may remain in the source checkout. \(cleanup.error ?? "")"
                let destinationSummary = destinationAlreadyMatched
                    ? "The destination already contained the exact task state."
                    : "Copied \(copied) local file\(copied == 1 ? "" : "s")."
                return ToolResult(
                    ok: true,
                    stdout: "Handed off task changes to \(destinationRoot.path). "
                        + "\(historyTransfer.summary(for: plan.historyTransition)) "
                        + "\(destinationSummary)\(warning)\n",
                    stderr: cleanup.ok ? "" : cleanup.error ?? "",
                    artifacts: [destinationRoot.path]
                )
            } catch {
                let snapshotRollback = destinationAlreadyMatched
                    ? ToolResult(ok: true)
                    : snapshotApplier.rollback(snapshot, at: destinationRoot)
                let historyRollback = historyTransfer.rollback(
                    plan.historyTransition,
                    at: destinationRoot
                )
                let rollbackErrors = [snapshotRollback, historyRollback]
                    .filter { !$0.ok }
                    .compactMap(\.error)
                let rollbackDetail = rollbackErrors.isEmpty
                    ? ""
                    : " Destination rollback also failed: \(rollbackErrors.joined(separator: "; "))"
                return ToolResult(ok: false, error: "\(error)\(rollbackDetail)")
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryRoot)
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func cleanSource(
        _ snapshot: ManagedWorktreeTransferSnapshot,
        sourceRoot: URL
    ) -> ToolResult {
        let unstaged = reversePatch(snapshot.unstagedPatchURL, staged: false, sourceRoot: sourceRoot)
        guard unstaged.ok else { return unstaged }
        let staged = reversePatch(snapshot.stagedPatchURL, staged: true, sourceRoot: sourceRoot)
        guard staged.ok else { return staged }

        var errors = [String]()
        for file in snapshot.files {
            guard let source = WorkspaceBoundary.safeURL(file.relativePath, root: sourceRoot),
                  FileManager.default.fileExists(atPath: source.path) else {
                continue
            }
            do {
                guard try fileStillMatchesSnapshot(source, snapshot: file.snapshotURL) else {
                    errors.append("\(file.relativePath): changed during handoff; left in source")
                    continue
                }
                try FileManager.default.removeItem(at: source)
            } catch {
                errors.append("\(file.relativePath): \(error.localizedDescription)")
            }
        }
        return errors.isEmpty
            ? ToolResult(ok: true)
            : ToolResult(ok: false, error: errors.joined(separator: "; "))
    }

    private func reversePatch(_ patchURL: URL, staged: Bool, sourceRoot: URL) -> ToolResult {
        let size = (try? patchURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { return ToolResult(ok: true) }
        var arguments = ["apply", "--reverse", "--binary", "--whitespace=nowarn"]
        if staged {
            arguments.append("--index")
        }
        arguments.append(patchURL.path)
        let result = runner.runGit(arguments, cwd: sourceRoot, timeoutSeconds: 30)
        guard result.ok else {
            return ToolResult(
                ok: false,
                error: "Could not remove the transferred \(staged ? "staged" : "unstaged") "
                    + "changes from the source: \(result.error ?? result.stderr)"
            )
        }
        return ToolResult(ok: true)
    }

    private func fileStillMatchesSnapshot(_ source: URL, snapshot: URL) throws -> Bool {
        let sourceData = try Data(contentsOf: source, options: .mappedIfSafe)
        let snapshotData = try Data(contentsOf: snapshot, options: .mappedIfSafe)
        guard sourceData == snapshotData else { return false }
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let snapshotAttributes = try FileManager.default.attributesOfItem(atPath: snapshot.path)
        return (sourceAttributes[.posixPermissions] as? NSNumber)?.intValue
            == (snapshotAttributes[.posixPermissions] as? NSNumber)?.intValue
    }
}
