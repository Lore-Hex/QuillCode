import Foundation
import QuillCodeCore
import QuillCodeTools

typealias WorkspacePullRequestLookup = @Sendable (URL, String) async -> GitHubPullRequestLookup

@MainActor
extension QuillCodeWorkspaceModel {
    func scheduleSelectedPullRequestReconciliation() {
        pullRequestReconciliationTask?.cancel()
        guard selectedPullRequestReconciliationCandidate() != nil else {
            pullRequestReconciliationTask = nil
            return
        }

        let lookup = Self.livePullRequestLookup()
        pullRequestReconciliationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let shouldPollAgain = await self?.reconcileSelectedPullRequestOnce(using: lookup) else {
                    return
                }
                guard shouldPollAgain, !Task.isCancelled else { return }
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
            }
        }
    }

    @discardableResult
    func reconcileSelectedPullRequestOnce(using lookup: WorkspacePullRequestLookup) async -> Bool {
        guard let candidate = selectedPullRequestReconciliationCandidate() else { return false }
        let result = await lookup(candidate.lookupRoot, String(candidate.pullRequestNumber))
        guard !Task.isCancelled else { return false }
        return applySelectedPullRequestReconciliation(result, candidate: candidate)
    }

    private static func livePullRequestLookup() -> WorkspacePullRequestLookup {
        let inspector = GitHubPullRequestInspector()
        return { root, selector in
            await Task.detached(priority: .utility) {
                inspector.inspect(cwd: root, selector: selector)
            }.value
        }
    }

    private func selectedPullRequestReconciliationCandidate() -> PullRequestReconciliationCandidate? {
        guard let threadID = root.selectedThreadID,
              let thread = selectedThread,
              !thread.isArchived,
              let pullRequest = thread.pullRequest,
              let project = selectedProject,
              !project.isRemote
        else { return nil }

        let missingMergedWorktree = pullRequest.status == .merged
            && thread.worktree.map { !FileManager.default.fileExists(atPath: $0.path) } == true
        guard !pullRequest.status.isTerminal || missingMergedWorktree else { return nil }

        let projectRoot = URL(fileURLWithPath: project.path).standardizedFileURL
        let lookupRoot = thread.worktree.flatMap { binding in
            binding.isResolvable ? URL(fileURLWithPath: binding.path).standardizedFileURL : nil
        } ?? projectRoot
        return PullRequestReconciliationCandidate(
            threadID: threadID,
            lookupRoot: lookupRoot,
            pullRequestNumber: pullRequest.number,
            headBranch: pullRequest.headBranch
        )
    }

    private func applySelectedPullRequestReconciliation(
        _ lookup: GitHubPullRequestLookup,
        candidate: PullRequestReconciliationCandidate
    ) -> Bool {
        guard root.selectedThreadID == candidate.threadID,
              let current = selectedThread?.pullRequest,
              current.number == candidate.pullRequestNumber,
              lookup.warning == nil,
              let pullRequest = lookup.pullRequest,
              pullRequest.number == candidate.pullRequestNumber,
              pullRequest.headBranch == candidate.headBranch
        else { return false }

        let refreshed = pullRequest.durableLink()
        if !current.hasSameRemoteState(as: refreshed) {
            setSelectedThreadPullRequest(refreshed)
        }

        guard refreshed.status == .merged else {
            return refreshed.status == .queued
        }
        clearAlreadyMissingMergedWorktree(pullRequest: pullRequest)
        return false
    }

    private func clearAlreadyMissingMergedWorktree(
        pullRequest: GitBranchPublicationPullRequest
    ) {
        guard let worktree = selectedThread?.worktree,
              !FileManager.default.fileExists(atPath: worktree.path)
        else { return }

        let coordinator = WorkspaceManagedWorktreePullRequestCoordinator(
            model: self,
            inspectBranch: { _, _, _ in
                throw PullRequestReconciliationError.unexpectedBranchInspection
            },
            inspectPullRequest: { _, _ in
                GitHubPullRequestLookup(pullRequest: pullRequest)
            },
            runTool: { _, _, _ in
                ToolResult(ok: false, error: "Unexpected tool call during stale worktree cleanup.")
            },
            fileExists: { _ in false }
        )
        _ = coordinator.cleanUpMergedSelectedThread()
    }
}

private struct PullRequestReconciliationCandidate: Sendable {
    let threadID: UUID
    let lookupRoot: URL
    let pullRequestNumber: Int
    let headBranch: String
}

private enum PullRequestReconciliationError: Error {
    case unexpectedBranchInspection
}

private extension PullRequestLink {
    func hasSameRemoteState(as other: PullRequestLink) -> Bool {
        number == other.number
            && title == other.title
            && url == other.url
            && status == other.status
            && baseBranch == other.baseBranch
            && headBranch == other.headBranch
            && headCommit == other.headCommit
            && mergeState == other.mergeState
    }
}
