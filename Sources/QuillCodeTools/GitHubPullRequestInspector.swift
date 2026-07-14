import Foundation
import QuillCodeCore

public struct GitBranchPublicationPullRequest: Sendable, Hashable {
    public let number: Int
    public let title: String
    public let url: String
    public let state: String
    public let isDraft: Bool
    public let baseBranch: String
    public let headBranch: String
    public let headCommit: String
    public let mergeStateStatus: String?
    public let autoMergeEnabled: Bool

    public init(
        number: Int,
        title: String,
        url: String,
        state: String,
        isDraft: Bool,
        baseBranch: String,
        headBranch: String,
        headCommit: String = "",
        mergeStateStatus: String? = nil,
        autoMergeEnabled: Bool = false
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.isDraft = isDraft
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.headCommit = headCommit
        self.mergeStateStatus = mergeStateStatus
        self.autoMergeEnabled = autoMergeEnabled
    }

    public var lifecycleStatus: PullRequestLifecycleStatus {
        switch state.uppercased() {
        case "MERGED":
            return .merged
        case "CLOSED":
            return .closed
        default:
            if isDraft { return .draft }
            if autoMergeEnabled { return .queued }
            return .open
        }
    }

    public var isOpen: Bool {
        lifecycleStatus == .open || lifecycleStatus == .draft || lifecycleStatus == .queued
    }

    public func durableLink(updatedAt: Date = Date()) -> PullRequestLink {
        PullRequestLink(
            number: number,
            title: title,
            url: url,
            status: lifecycleStatus,
            baseBranch: baseBranch,
            headBranch: headBranch,
            headCommit: headCommit,
            mergeState: mergeStateStatus,
            updatedAt: updatedAt
        )
    }
}

public struct GitHubPullRequestLookup: Sendable, Hashable {
    public let pullRequest: GitBranchPublicationPullRequest?
    public let warning: String?

    public init(pullRequest: GitBranchPublicationPullRequest?, warning: String? = nil) {
        self.pullRequest = pullRequest
        self.warning = warning
    }
}

public struct GitHubPullRequestInspector: Sendable {
    private let runner: GitProcessRunner

    public init(githubCLIExecutable: URL? = nil) {
        self.runner = GitProcessRunner(githubCLIExecutable: githubCLIExecutable)
    }

    public func inspect(cwd: URL, selector: String) -> GitHubPullRequestLookup {
        let result = runner.runGitHub(
            [
                "pr", "view", selector,
                "--json", "number,title,url,state,isDraft,baseRefName,headRefName,headRefOid,mergeStateStatus,autoMergeRequest"
            ],
            cwd: cwd,
            timeoutSeconds: 30
        )
        guard result.ok else {
            let detail = Self.conciseDetail(result)
            return Self.isMissingPullRequest(detail)
                ? GitHubPullRequestLookup(pullRequest: nil)
                : GitHubPullRequestLookup(
                    pullRequest: nil,
                    warning: detail.isEmpty ? "Could not check for an existing pull request." : detail
                )
        }
        do {
            let payload = try JSONDecoder().decode(PullRequestPayload.self, from: Data(result.stdout.utf8))
            return GitHubPullRequestLookup(pullRequest: GitBranchPublicationPullRequest(
                number: payload.number,
                title: payload.title,
                url: payload.url,
                state: payload.state,
                isDraft: payload.isDraft,
                baseBranch: payload.baseRefName,
                headBranch: payload.headRefName,
                headCommit: payload.headRefOid ?? "",
                mergeStateStatus: payload.mergeStateStatus,
                autoMergeEnabled: payload.autoMergeRequest != nil
            ))
        } catch {
            return GitHubPullRequestLookup(
                pullRequest: nil,
                warning: "GitHub returned an unreadable pull request summary."
            )
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

    private static func isMissingPullRequest(_ detail: String) -> Bool {
        let normalized = detail.lowercased()
        return [
            "no pull requests found",
            "could not resolve to a pull request",
            "no open pull requests"
        ].contains { normalized.contains($0) }
    }
}

private struct PullRequestPayload: Decodable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool
    let baseRefName: String
    let headRefName: String
    let headRefOid: String?
    let mergeStateStatus: String?
    let autoMergeRequest: AutoMergeRequestPayload?
}

private struct AutoMergeRequestPayload: Decodable {}
