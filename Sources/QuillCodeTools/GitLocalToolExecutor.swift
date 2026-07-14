import Foundation
import QuillCodeCore

public struct GitLocalToolExecutor: Sendable {
    private let shell: ShellToolExecutor
    private let runner: GitProcessRunner

    public init(
        shell: ShellToolExecutor = ShellToolExecutor(),
        runner: GitProcessRunner = GitProcessRunner()
    ) {
        self.shell = shell
        self.runner = runner
    }

    public func status(cwd: URL) -> ToolResult {
        shell.run(.init(command: "git status --short --branch", cwd: cwd, timeoutSeconds: 15))
    }

    public func diff(
        cwd: URL,
        staged: Bool = false,
        commit: String? = nil,
        baseBranch: String? = nil
    ) -> ToolResult {
        do {
            let options = try GitDiffOptions(staged: staged, commit: commit, baseBranch: baseBranch)
            return runGit(options.gitArguments, cwd: cwd, timeoutSeconds: 20)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func fetch(cwd: URL, remote: String? = nil, prune: Bool = false) -> ToolResult {
        do {
            return runGit(
                try GitFetchOptions(remote: remote, prune: prune).gitArguments,
                cwd: cwd,
                timeoutSeconds: 120
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func pull(
        cwd: URL,
        remote: String? = nil,
        branch: String? = nil,
        ffOnly: Bool = true
    ) -> ToolResult {
        do {
            return runGit(
                try GitPullOptions(remote: remote, branch: branch, ffOnly: ffOnly).gitArguments,
                cwd: cwd,
                timeoutSeconds: 180
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func listBranches(cwd: URL, includeRemote: Bool = true) -> ToolResult {
        var arguments = ["branch"]
        if includeRemote {
            arguments.append("--all")
        }
        arguments.append("--format=%(HEAD)%09%(refname:short)%09%(upstream:short)")
        return runGit(arguments, cwd: cwd, timeoutSeconds: 15)
    }

    public func switchBranch(
        cwd: URL,
        branch: String,
        create: Bool = false,
        startPoint: String? = nil
    ) -> ToolResult {
        do {
            let branchName = try GitInputValidator.safeName(branch)
            let resolvedStartPoint = try GitInputValidator.trimmedNonEmpty(startPoint).map(GitInputValidator.safeName)
            guard create || resolvedStartPoint == nil else {
                throw GitToolError.branchStartPointRequiresCreate
            }

            var arguments = ["switch"]
            if create {
                arguments += ["-c", branchName]
                if let resolvedStartPoint {
                    arguments.append(resolvedStartPoint)
                }
            } else {
                arguments.append(branchName)
            }
            return runGit(arguments, cwd: cwd, timeoutSeconds: 30)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func stage(cwd: URL, path: String) -> ToolResult {
        do {
            return runGit(["add", "--", try GitInputValidator.safeRelativePath(path, cwd: cwd)], cwd: cwd, timeoutSeconds: 20)
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
            arguments += ["--", try GitInputValidator.safeRelativePath(path, cwd: cwd)]
            return runGit(arguments, cwd: cwd, timeoutSeconds: 20)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func commit(cwd: URL, message: String) -> ToolResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolResult(ok: false, error: String(describing: GitToolError.emptyCommitMessage))
        }
        return runGit(["commit", "-m", trimmed], cwd: cwd, timeoutSeconds: 30)
    }

    public func push(
        cwd: URL,
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool = false
    ) -> ToolResult {
        do {
            let remoteName = try GitInputValidator.safeName(GitInputValidator.trimmedNonEmpty(remote) ?? "origin")
            let branchName: String
            if let branch = GitInputValidator.trimmedNonEmpty(branch) {
                branchName = try GitInputValidator.safeName(branch)
            } else {
                branchName = try currentBranchName(cwd: cwd)
            }
            guard !branchName.isEmpty else {
                throw GitToolError.emptyBranch
            }

            var arguments = ["push"]
            if setUpstream {
                arguments.append("-u")
            }
            arguments += [remoteName, branchName]
            return runGit(arguments, cwd: cwd, timeoutSeconds: 120)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func currentBranchName(cwd: URL) throws -> String {
        let result = runGit(["branch", "--show-current"], cwd: cwd, timeoutSeconds: 10)
        guard result.ok else {
            throw GitToolError.noCurrentBranch
        }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitToolError.noCurrentBranch
        }
        return try GitInputValidator.safeName(branch)
    }

    private func runGit(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        runner.runGit(arguments, cwd: cwd, timeoutSeconds: timeoutSeconds)
    }
}
