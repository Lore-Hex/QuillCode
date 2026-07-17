import Foundation
import QuillCodeCore
import QuillCodeTools

struct AppServerGitDiffToRemoteLimits: Sendable, Equatable {
    var maximumDiffBytes = 8 * 1_024 * 1_024
    var maximumUntrackedInventoryBytes = 2 * 1_024 * 1_024
    var maximumUntrackedFiles = 2_048
}

struct AppServerGitDiffToRemoteSnapshot: Sendable, Equatable {
    var sha: String
    var diff: String

    var jsonValue: CLIJSONValue {
        .object([
            "sha": .string(sha),
            "diff": .string(diff)
        ])
    }
}

struct AppServerGitDiffToRemoteReader: Sendable {
    private let runner: GitProcessRunner
    private let limits: AppServerGitDiffToRemoteLimits

    init(
        runner: GitProcessRunner = GitProcessRunner(),
        limits: AppServerGitDiffToRemoteLimits = AppServerGitDiffToRemoteLimits()
    ) {
        self.runner = runner
        self.limits = limits
    }

    func read(cwd: URL) throws -> AppServerGitDiffToRemoteSnapshot {
        let root = cwd.standardizedFileURL
        guard isDirectory(root) else {
            throw AppServerGitDiffToRemoteError.invalidRepository
        }

        let upstream = try requiredGit(
            ["rev-parse", "--verify", "@{upstream}^{commit}"],
            cwd: root
        ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !upstream.isEmpty else {
            throw AppServerGitDiffToRemoteError.invalidRepository
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-git-diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var diff = Data()
        try appendPatch(
            arguments: [
                "diff", "--binary", "--no-color", "--no-ext-diff", "--no-textconv",
                upstream, "--"
            ],
            output: temporaryDirectory.appendingPathComponent("tracked.patch"),
            cwd: root,
            acceptingDifferenceExit: false,
            to: &diff
        )

        let untracked = try untrackedPaths(cwd: root)
        for (index, path) in untracked.enumerated() {
            let safePath: String
            do {
                safePath = try GitInputValidator.safeRelativePath(path, cwd: root)
            } catch {
                throw AppServerGitDiffToRemoteError.invalidRepository
            }
            try appendPatch(
                arguments: [
                    "diff", "--no-index", "--binary", "--no-color", "--no-ext-diff", "--no-textconv",
                    "--", "/dev/null", safePath
                ],
                output: temporaryDirectory.appendingPathComponent("untracked-\(index).patch"),
                cwd: root,
                acceptingDifferenceExit: true,
                to: &diff
            )
        }

        return AppServerGitDiffToRemoteSnapshot(
            sha: upstream,
            diff: String(decoding: diff, as: UTF8.self)
        )
    }

    private func untrackedPaths(cwd: URL) throws -> [String] {
        let result = try requiredGit(
            ["ls-files", "--others", "--exclude-standard", "-z"],
            cwd: cwd
        )
        guard result.stdout.utf8.count <= limits.maximumUntrackedInventoryBytes,
              !result.stdout.contains("\u{FFFD}")
        else {
            throw AppServerGitDiffToRemoteError.outputTooLarge
        }
        let paths = result.stdout
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
        guard paths.count <= limits.maximumUntrackedFiles else {
            throw AppServerGitDiffToRemoteError.outputTooLarge
        }
        return paths
    }

    private func appendPatch(
        arguments: [String],
        output: URL,
        cwd: URL,
        acceptingDifferenceExit: Bool,
        to diff: inout Data
    ) throws {
        var command = arguments
        if let separator = command.firstIndex(of: "--") {
            command.insert("--output=\(output.path)", at: separator)
        } else {
            command.append("--output=\(output.path)")
        }
        let result = runner.runGit(
            command,
            cwd: cwd,
            timeoutSeconds: 30
        )
        let succeeded = result.ok || (acceptingDifferenceExit && result.exitCode == 1)
        guard succeeded else {
            throw AppServerGitDiffToRemoteError.invalidRepository
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard diff.count <= limits.maximumDiffBytes,
              byteCount <= limits.maximumDiffBytes - diff.count
        else {
            throw AppServerGitDiffToRemoteError.outputTooLarge
        }
        let patch = try Data(contentsOf: output, options: .mappedIfSafe)
        guard patch.count <= limits.maximumDiffBytes - diff.count else {
            throw AppServerGitDiffToRemoteError.outputTooLarge
        }
        diff.append(patch)
    }

    private func requiredGit(_ arguments: [String], cwd: URL) throws -> ToolResult {
        let result = runner.runGit(arguments, cwd: cwd, timeoutSeconds: 30)
        guard result.ok else {
            throw AppServerGitDiffToRemoteError.invalidRepository
        }
        return result
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

enum AppServerGitDiffToRemoteError: Error, Equatable {
    case invalidRepository
    case outputTooLarge
}

extension AppServerSession {
    func gitDiffToRemote(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        guard let object = raw.objectValue else {
            throw AppServerRPCError.invalidRequest("Invalid request: expected an object")
        }
        guard let cwdValue = object["cwd"] else {
            throw AppServerRPCError.invalidRequest("Invalid request: missing field `cwd`")
        }
        guard let rawCWD = cwdValue.stringValue else {
            throw AppServerRPCError.invalidRequest("Invalid request: `cwd` must be a path string")
        }

        let cwd = URL(fileURLWithPath: rawCWD, relativeTo: currentDirectory).standardizedFileURL
        do {
            guard !rawCWD.isEmpty else {
                throw AppServerGitDiffToRemoteError.invalidRepository
            }
            return try AppServerGitDiffToRemoteReader().read(cwd: cwd).jsonValue
        } catch {
            throw AppServerRPCError.invalidRequest(
                "failed to compute git diff to remote for cwd: \(String(reflecting: rawCWD))"
            )
        }
    }
}
