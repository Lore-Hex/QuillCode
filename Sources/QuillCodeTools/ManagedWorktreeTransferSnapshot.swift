import Foundation
import QuillCodeCore

enum ManagedWorktreeLocalFilePolicy: Sendable, Hashable {
    case managedCreation
    case handoff
}

struct ManagedWorktreeTransferFile: Sendable, Hashable {
    var relativePath: String
    var snapshotURL: URL
}

private struct ManagedWorktreeSourceFile {
    var relativePath: String
    var sourceURL: URL
}

struct ManagedWorktreeTransferSnapshot: Sendable, Hashable {
    var stagedPatchURL: URL
    var unstagedPatchURL: URL
    var files: [ManagedWorktreeTransferFile]
    var skippedSymlinkCount: Int

    func hasSameContent(as other: ManagedWorktreeTransferSnapshot) throws -> Bool {
        guard try data(at: stagedPatchURL) == data(at: other.stagedPatchURL),
              try data(at: unstagedPatchURL) == data(at: other.unstagedPatchURL) else {
            return false
        }
        let ownFiles = Dictionary(uniqueKeysWithValues: files.map { ($0.relativePath, $0.snapshotURL) })
        let otherFiles = Dictionary(uniqueKeysWithValues: other.files.map { ($0.relativePath, $0.snapshotURL) })
        guard Set(ownFiles.keys) == Set(otherFiles.keys) else { return false }
        for path in ownFiles.keys {
            guard let ownURL = ownFiles[path],
                  let otherURL = otherFiles[path],
                  try data(at: ownURL) == data(at: otherURL),
                  try permissions(at: ownURL) == permissions(at: otherURL) else {
                return false
            }
        }
        return true
    }

    static func capture(
        sourceRoot: URL,
        temporaryDirectory: URL,
        runner: GitProcessRunner,
        localFilePolicy: ManagedWorktreeLocalFilePolicy = .managedCreation,
        limits: ManagedWorktreeTransferLimits = ManagedWorktreeTransferLimits()
    ) throws -> ManagedWorktreeTransferSnapshot {
        let stagedPatchURL = temporaryDirectory.appendingPathComponent("staged.patch")
        let unstagedPatchURL = temporaryDirectory.appendingPathComponent("unstaged.patch")
        try capturePatch(
            arguments: ["diff", "--binary", "--cached", "--output=\(stagedPatchURL.path)", "HEAD", "--"],
            label: "staged",
            destination: stagedPatchURL,
            sourceRoot: sourceRoot,
            runner: runner,
            limits: limits
        )
        try capturePatch(
            arguments: ["diff", "--binary", "--output=\(unstagedPatchURL.path)", "--"],
            label: "unstaged",
            destination: unstagedPatchURL,
            sourceRoot: sourceRoot,
            runner: runner,
            limits: limits
        )

        let inventory = try ManagedWorktreeFileInventory.capture(
            sourceRoot: sourceRoot,
            runner: runner,
            policy: localFilePolicy,
            limits: limits
        )
        let files = try inventory.freeze(
            sourceRoot: sourceRoot,
            snapshotRoot: temporaryDirectory.appendingPathComponent("files"),
            limits: limits
        )
        return ManagedWorktreeTransferSnapshot(
            stagedPatchURL: stagedPatchURL,
            unstagedPatchURL: unstagedPatchURL,
            files: files,
            skippedSymlinkCount: inventory.skippedSymlinkCount
        )
    }

    private static func capturePatch(
        arguments: [String],
        label: String,
        destination: URL,
        sourceRoot: URL,
        runner: GitProcessRunner,
        limits: ManagedWorktreeTransferLimits
    ) throws {
        let result = runner.runGit(arguments, cwd: sourceRoot, timeoutSeconds: 30)
        guard result.ok else {
            throw ManagedWorktreeMaterializationError.commandFailed("\(label) snapshot", result)
        }
        let bytes = try fileSize(destination, label: label)
        guard bytes <= limits.maximumPatchBytes else {
            throw ManagedWorktreeMaterializationError.patchTooLarge(label, bytes)
        }
    }

    private static func fileSize(_ url: URL, label: String) throws -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values.fileSize ?? 0)
        } catch {
            throw ManagedWorktreeMaterializationError.fileInspectionFailed(label, error.localizedDescription)
        }
    }

    private func data(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ManagedWorktreeMaterializationError.fileInspectionFailed(
                url.lastPathComponent,
                error.localizedDescription
            )
        }
    }

    private func permissions(at url: URL) throws -> Int? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.posixPermissions] as? NSNumber)?.intValue
        } catch {
            throw ManagedWorktreeMaterializationError.fileInspectionFailed(
                url.lastPathComponent,
                error.localizedDescription
            )
        }
    }
}

private struct ManagedWorktreeFileInventory {
    var files: [ManagedWorktreeSourceFile]
    var skippedSymlinkCount: Int

    static func capture(
        sourceRoot: URL,
        runner: GitProcessRunner,
        policy: ManagedWorktreeLocalFilePolicy,
        limits: ManagedWorktreeTransferLimits
    ) throws -> ManagedWorktreeFileInventory {
        var candidates = try paths(
            arguments: ["ls-files", "--others", "--exclude-standard", "-z"],
            operation: "untracked-file inventory",
            sourceRoot: sourceRoot,
            runner: runner,
            limits: limits
        )
        if policy == .managedCreation {
            candidates.formUnion(try includedIgnoredPaths(sourceRoot: sourceRoot, runner: runner, limits: limits))
            if isIgnored("AGENTS.override.md", sourceRoot: sourceRoot, runner: runner) {
                candidates.insert("AGENTS.override.md")
            }
        }

        var files = [ManagedWorktreeSourceFile]()
        var skippedSymlinkCount = 0
        var totalBytes: Int64 = 0
        for candidate in candidates.sorted() {
            guard !candidate.contains("\u{FFFD}") else {
                throw ManagedWorktreeMaterializationError.unsupportedFilename(candidate)
            }
            let relativePath: String
            do {
                relativePath = try GitInputValidator.safeRelativePath(candidate, cwd: sourceRoot)
            } catch {
                throw ManagedWorktreeMaterializationError.unsafeSource(candidate)
            }
            let sourceURL = sourceRoot.appendingPathComponent(relativePath)
            let values: URLResourceValues
            do {
                values = try sourceURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey
                ])
            } catch {
                throw ManagedWorktreeMaterializationError.fileInspectionFailed(candidate, error.localizedDescription)
            }
            if values.isSymbolicLink == true {
                skippedSymlinkCount += 1
                continue
            }
            guard values.isRegularFile == true, WorkspaceBoundary.isWithin(sourceURL, root: sourceRoot) else {
                throw ManagedWorktreeMaterializationError.unsafeSource(candidate)
            }
            let byteCount = Int64(values.fileSize ?? 0)
            guard byteCount <= limits.maximumFileBytes else {
                throw ManagedWorktreeMaterializationError.fileTooLarge(relativePath, byteCount)
            }
            totalBytes += byteCount
            guard totalBytes <= limits.maximumTotalFileBytes else {
                throw ManagedWorktreeMaterializationError.totalFilesTooLarge(totalBytes)
            }
            files.append(.init(relativePath: relativePath, sourceURL: sourceURL))
            guard files.count <= limits.maximumFiles else {
                throw ManagedWorktreeMaterializationError.tooManyFiles(files.count)
            }
        }
        return ManagedWorktreeFileInventory(files: files, skippedSymlinkCount: skippedSymlinkCount)
    }

    func freeze(
        sourceRoot: URL,
        snapshotRoot: URL,
        limits: ManagedWorktreeTransferLimits
    ) throws -> [ManagedWorktreeTransferFile] {
        var snapshots = [ManagedWorktreeTransferFile]()
        var totalBytes: Int64 = 0
        for file in files {
            guard WorkspaceBoundary.isWithin(file.sourceURL, root: sourceRoot),
                  let destination = WorkspaceBoundary.safeURL(file.relativePath, root: snapshotRoot) else {
                throw ManagedWorktreeMaterializationError.unsafeSource(file.relativePath)
            }
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: file.sourceURL, to: destination)
            } catch {
                throw ManagedWorktreeMaterializationError.fileCopyFailed(
                    file.relativePath,
                    error.localizedDescription
                )
            }

            let values: URLResourceValues
            do {
                values = try destination.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey
                ])
            } catch {
                throw ManagedWorktreeMaterializationError.fileInspectionFailed(
                    file.relativePath,
                    error.localizedDescription
                )
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ManagedWorktreeMaterializationError.sourceChanged(file.relativePath)
            }
            let byteCount = Int64(values.fileSize ?? 0)
            guard byteCount <= limits.maximumFileBytes else {
                throw ManagedWorktreeMaterializationError.fileTooLarge(file.relativePath, byteCount)
            }
            totalBytes += byteCount
            guard totalBytes <= limits.maximumTotalFileBytes else {
                throw ManagedWorktreeMaterializationError.totalFilesTooLarge(totalBytes)
            }
            snapshots.append(.init(relativePath: file.relativePath, snapshotURL: destination))
        }
        return snapshots
    }

    private static func includedIgnoredPaths(
        sourceRoot: URL,
        runner: GitProcessRunner,
        limits: ManagedWorktreeTransferLimits
    ) throws -> Set<String> {
        let includeURL = sourceRoot.appendingPathComponent(".worktreeinclude")
        guard let values = try? includeURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]), values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= 64 * 1_024 else {
            return []
        }
        let matches = try paths(
            arguments: ["ls-files", "--others", "--ignored", "--exclude-from=.worktreeinclude", "-z"],
            operation: ".worktreeinclude inventory",
            sourceRoot: sourceRoot,
            runner: runner,
            limits: limits
        )
        return Set(matches.filter { isIgnored($0, sourceRoot: sourceRoot, runner: runner) })
    }

    private static func paths(
        arguments: [String],
        operation: String,
        sourceRoot: URL,
        runner: GitProcessRunner,
        limits: ManagedWorktreeTransferLimits
    ) throws -> Set<String> {
        let result = runner.runGit(arguments, cwd: sourceRoot, timeoutSeconds: 20)
        guard result.ok else {
            throw ManagedWorktreeMaterializationError.commandFailed(operation, result)
        }
        let bytes = result.stdout.utf8.count
        guard bytes <= limits.maximumCandidateListBytes else {
            throw ManagedWorktreeMaterializationError.candidateListTooLarge(bytes)
        }
        return Set(result.stdout.split(separator: "\0").map(String.init))
    }

    private static func isIgnored(_ path: String, sourceRoot: URL, runner: GitProcessRunner) -> Bool {
        runner.runGit(["check-ignore", "-q", "--", path], cwd: sourceRoot, timeoutSeconds: 10).ok
    }
}
