import Foundation
import QuillCodeCore

public struct GitBranchPublicationInspection: Sendable, Hashable {
    public let branch: String
    public let baseBranch: String?
    public let headCommit: String
    public let hasUncommittedChanges: Bool
    public let commitsAheadOfBase: Int?
    public let upstream: String?
    public let commitsAheadOfUpstream: Int
    public let commitsBehindUpstream: Int
    public let pullRequest: GitBranchPublicationPullRequest?
    public let pullRequestLookupWarning: String?

    public init(
        branch: String,
        baseBranch: String?,
        headCommit: String = "",
        hasUncommittedChanges: Bool,
        commitsAheadOfBase: Int?,
        upstream: String?,
        commitsAheadOfUpstream: Int = 0,
        commitsBehindUpstream: Int = 0,
        pullRequest: GitBranchPublicationPullRequest? = nil,
        pullRequestLookupWarning: String? = nil
    ) {
        self.branch = branch
        self.baseBranch = baseBranch
        self.headCommit = headCommit
        self.hasUncommittedChanges = hasUncommittedChanges
        self.commitsAheadOfBase = commitsAheadOfBase
        self.upstream = upstream
        self.commitsAheadOfUpstream = commitsAheadOfUpstream
        self.commitsBehindUpstream = commitsBehindUpstream
        self.pullRequest = pullRequest
        self.pullRequestLookupWarning = pullRequestLookupWarning
    }

    public var openPullRequest: GitBranchPublicationPullRequest? {
        pullRequest?.isOpen == true ? pullRequest : nil
    }

    public var needsPush: Bool {
        upstream == nil || commitsAheadOfUpstream > 0
    }

    public var upstreamRemote: String? {
        guard let upstream,
              let separator = upstream.firstIndex(of: "/"),
              separator != upstream.startIndex
        else { return nil }
        return String(upstream[..<separator])
    }
}

public struct GitBranchPublicationInspector: Sendable {
    private let runner: GitProcessRunner
    private let pullRequestInspector: GitHubPullRequestInspector

    public init(githubCLIExecutable: URL? = nil) {
        self.runner = GitProcessRunner(githubCLIExecutable: githubCLIExecutable)
        self.pullRequestInspector = GitHubPullRequestInspector(githubCLIExecutable: githubCLIExecutable)
    }

    public func inspect(
        cwd: URL,
        expectedBranch: String,
        baseBranch: String?
    ) throws -> GitBranchPublicationInspection {
        try inspect(
            cwd: cwd,
            expectedBranch: expectedBranch,
            baseBranch: baseBranch,
            includesPullRequest: true
        )
    }

    public func inspectBranchState(
        cwd: URL,
        expectedBranch: String,
        baseBranch: String?
    ) throws -> GitBranchPublicationInspection {
        try inspect(
            cwd: cwd,
            expectedBranch: expectedBranch,
            baseBranch: baseBranch,
            includesPullRequest: false
        )
    }

    private func inspect(
        cwd: URL,
        expectedBranch: String,
        baseBranch: String?,
        includesPullRequest: Bool
    ) throws -> GitBranchPublicationInspection {
        let expected = try validatedName(expectedBranch)
        let current = try currentBranch(cwd: cwd)
        guard current == expected else {
            throw GitBranchPublicationInspectionError.branchChanged(expected: expected, actual: current)
        }

        let status = try requiredGit(
            ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
            cwd: cwd,
            operation: "working-tree inspection"
        )
        let headCommit = try requiredGit(
            ["rev-parse", "HEAD"],
            cwd: cwd,
            operation: "HEAD inspection"
        ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = resolvedBaseBranch(baseBranch, headBranch: expected, cwd: cwd)
        let aheadOfBase = try base.map {
            try integerOutput(
                requiredGit(["rev-list", "--count", "\($0)..HEAD"], cwd: cwd, operation: "base comparison"),
                operation: "base comparison"
            )
        }
        let upstream = optionalGitOutput(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            cwd: cwd
        )
        let upstreamCounts = try upstream.map { try upstreamComparison($0, cwd: cwd) }
            ?? (behind: 0, ahead: 0)
        let pullRequestLookup = includesPullRequest
            ? pullRequestInspector.inspect(cwd: cwd, selector: expected)
            : GitHubPullRequestLookup(pullRequest: nil)

        return GitBranchPublicationInspection(
            branch: expected,
            baseBranch: base,
            headCommit: headCommit,
            hasUncommittedChanges: !status.stdout.isEmpty,
            commitsAheadOfBase: aheadOfBase,
            upstream: upstream,
            commitsAheadOfUpstream: upstreamCounts.ahead,
            commitsBehindUpstream: upstreamCounts.behind,
            pullRequest: pullRequestLookup.pullRequest,
            pullRequestLookupWarning: pullRequestLookup.warning
        )
    }

    private func currentBranch(cwd: URL) throws -> String {
        let result = try requiredGit(
            ["branch", "--show-current"],
            cwd: cwd,
            operation: "branch inspection"
        )
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitBranchPublicationInspectionError.detachedHead
        }
        return try validatedName(branch)
    }

    private func resolvedBaseBranch(_ value: String?, headBranch: String, cwd: URL) -> String? {
        guard let trimmed = GitInputValidator.trimmedNonEmpty(value),
              trimmed != "HEAD",
              trimmed != headBranch,
              let base = try? GitInputValidator.safeName(trimmed)
        else { return nil }
        let result = runner.runGit(
            ["rev-parse", "--verify", "--quiet", "\(base)^{commit}"],
            cwd: cwd,
            timeoutSeconds: 15
        )
        return result.ok ? base : nil
    }

    private func upstreamComparison(
        _ upstream: String,
        cwd: URL
    ) throws -> (behind: Int, ahead: Int) {
        let safeUpstream = try validatedName(upstream)
        let result = try requiredGit(
            ["rev-list", "--left-right", "--count", "\(safeUpstream)...HEAD"],
            cwd: cwd,
            operation: "upstream comparison"
        )
        let fields = result.stdout.split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 2,
              let behind = Int(fields[0]),
              let ahead = Int(fields[1])
        else {
            throw GitBranchPublicationInspectionError.malformedOutput("upstream comparison")
        }
        return (behind, ahead)
    }

    private func requiredGit(
        _ arguments: [String],
        cwd: URL,
        operation: String
    ) throws -> ToolResult {
        let result = runner.runGit(arguments, cwd: cwd, timeoutSeconds: 30)
        guard result.ok else {
            throw GitBranchPublicationInspectionError.commandFailed(
                operation: operation,
                detail: Self.conciseDetail(result)
            )
        }
        return result
    }

    private func optionalGitOutput(_ arguments: [String], cwd: URL) -> String? {
        let result = runner.runGit(arguments, cwd: cwd, timeoutSeconds: 15)
        guard result.ok else { return nil }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private func integerOutput(_ result: ToolResult, operation: String) throws -> Int {
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(output), value >= 0 else {
            throw GitBranchPublicationInspectionError.malformedOutput(operation)
        }
        return value
    }

    private func validatedName(_ value: String) throws -> String {
        do {
            return try GitInputValidator.safeName(value)
        } catch {
            throw GitBranchPublicationInspectionError.invalidBranch(value)
        }
    }

    private static func conciseDetail(_ result: ToolResult) -> String {
        let raw = [result.stderr, result.error ?? "", result.stdout]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let singleLine = raw
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(300))
    }
}

public enum GitBranchPublicationInspectionError: Error, CustomStringConvertible, Equatable {
    case invalidBranch(String)
    case detachedHead
    case branchChanged(expected: String, actual: String)
    case commandFailed(operation: String, detail: String)
    case malformedOutput(String)

    public var description: String {
        switch self {
        case .invalidBranch(let branch):
            return "Cannot publish the invalid Git branch '\(branch)'."
        case .detachedHead:
            return "This worktree is detached. Create a branch here before publishing."
        case .branchChanged(let expected, let actual):
            return "This task owns '\(expected)', but the worktree is currently on '\(actual)'. Switch back before publishing."
        case .commandFailed(let operation, let detail):
            return detail.isEmpty
                ? "Could not complete Git \(operation)."
                : "Could not complete Git \(operation): \(detail)"
        case .malformedOutput(let operation):
            return "Git returned unreadable output during \(operation)."
        }
    }
}
