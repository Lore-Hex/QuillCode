import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
struct WorkspaceManagedWorktreePullRequestCoordinator {
    typealias BranchInspectionProvider = (URL, String, String?) throws -> GitBranchPublicationInspection
    typealias PullRequestLookupProvider = (URL, String) -> GitHubPullRequestLookup
    typealias ToolRunner = (ToolCall, URL, URL?) -> ToolResult
    typealias FileExists = (String) -> Bool

    let model: QuillCodeWorkspaceModel
    private let inspectBranch: BranchInspectionProvider
    private let inspectPullRequest: PullRequestLookupProvider
    private let runTool: ToolRunner
    private let fileExists: FileExists

    init(model: QuillCodeWorkspaceModel) {
        let branchInspector = GitBranchPublicationInspector()
        let pullRequestInspector = GitHubPullRequestInspector()
        self.init(
            model: model,
            inspectBranch: {
                try branchInspector.inspectBranchState(cwd: $0, expectedBranch: $1, baseBranch: $2)
            },
            inspectPullRequest: { pullRequestInspector.inspect(cwd: $0, selector: $1) },
            runTool: { call, workspaceRoot, managedRoot in
                model.runToolCall(
                    call,
                    workspaceRoot: workspaceRoot,
                    managedWorktreeRoot: managedRoot
                )
            },
            fileExists: FileManager.default.fileExists(atPath:)
        )
    }

    init(
        model: QuillCodeWorkspaceModel,
        inspectBranch: @escaping BranchInspectionProvider,
        inspectPullRequest: @escaping PullRequestLookupProvider,
        runTool: @escaping ToolRunner,
        fileExists: @escaping FileExists = FileManager.default.fileExists(atPath:)
    ) {
        self.model = model
        self.inspectBranch = inspectBranch
        self.inspectPullRequest = inspectPullRequest
        self.runTool = runTool
        self.fileExists = fileExists
    }

    func refreshSelectedThread() -> Bool {
        guard let context = pullRequestContext() else { return false }
        guard let pullRequest = authoritativePullRequest(context: context) else { return false }
        model.setSelectedThreadPullRequest(pullRequest.durableLink())
        model.appendNotice("Pull request #\(pullRequest.number) is \(pullRequest.lifecycleStatus.label.lowercased()).")
        return true
    }

    func landSelectedThread() -> Bool {
        guard let linkedPullRequest = model.selectedThread?.pullRequest else {
            fail("Publish this branch before landing its pull request.")
            return false
        }
        guard let context = branchContext() else { return false }
        let inspection: GitBranchPublicationInspection
        do {
            inspection = try inspectBranch(context.worktreeRoot, context.branch, context.baseBranch)
        } catch {
            fail(String(describing: error))
            return false
        }
        if inspection.hasUncommittedChanges {
            _ = runTool(
                ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}"),
                context.worktreeRoot,
                context.authorizedManagedRoot
            )
            fail("Commit or restore all worktree changes before landing this pull request.")
            return false
        }
        if inspection.needsPush || inspection.commitsBehindUpstream > 0 {
            fail("Publish and synchronize this branch before landing its pull request.")
            return false
        }

        let lookupContext = PullRequestContext(
            projectRoot: context.projectRoot,
            lookupRoot: context.worktreeRoot,
            link: linkedPullRequest
        )
        guard let pullRequest = authoritativePullRequest(context: lookupContext) else { return false }
        model.setSelectedThreadPullRequest(pullRequest.durableLink())
        guard validateIdentity(pullRequest, inspection: inspection) else { return false }

        switch pullRequest.lifecycleStatus {
        case .draft:
            fail("Mark pull request #\(pullRequest.number) ready for review before landing it.")
            return false
        case .closed:
            fail("Pull request #\(pullRequest.number) is closed and cannot be landed.")
            return false
        case .merged:
            model.appendNotice("Pull request #\(pullRequest.number) is already merged. Its verified worktree can be cleaned up.")
            return true
        case .queued:
            model.appendNotice("Pull request #\(pullRequest.number) is already queued for merge.")
            return true
        case .open:
            break
        }

        let merge = runTool(
            ToolCall(
                name: ToolDefinition.gitPullRequestMerge.name,
                argumentsJSON: ToolArguments.json([
                    "selector": String(pullRequest.number),
                    "method": "squash",
                    "auto": true,
                    "deleteBranch": false
                ])
            ),
            context.worktreeRoot,
            context.authorizedManagedRoot
        )
        guard merge.ok else {
            fail("GitHub could not merge or queue pull request #\(pullRequest.number). Review the failed PR card and try again.")
            return false
        }

        var queuedLink = pullRequest.durableLink()
        queuedLink.status = .queued
        model.setSelectedThreadPullRequest(queuedLink)
        let refreshed = inspectPullRequest(context.worktreeRoot, String(pullRequest.number))
        if let refreshedPullRequest = refreshed.pullRequest {
            model.setSelectedThreadPullRequest(refreshedPullRequest.durableLink())
            model.appendNotice(landingNotice(for: refreshedPullRequest))
        } else {
            if let warning = refreshed.warning {
                model.appendNotice("GitHub status refresh warning: \(warning)")
            }
            model.appendNotice("Pull request #\(pullRequest.number) was submitted for merge. Refresh its status to confirm completion.")
        }
        return true
    }

    func cleanUpMergedSelectedThread() -> Bool {
        guard let context = cleanupContext() else { return false }
        guard let pullRequest = authoritativePullRequest(context: context.pullRequest) else { return false }
        model.setSelectedThreadPullRequest(pullRequest.durableLink())
        guard pullRequest.lifecycleStatus == .merged else {
            fail("Pull request #\(pullRequest.number) must be merged before its worktree can be cleaned up.")
            return false
        }

        guard fileExists(context.worktreeRoot.path) else {
            completeCleanup(context: context, removedWorktree: false)
            return true
        }

        let inspection: GitBranchPublicationInspection
        do {
            inspection = try inspectBranch(context.worktreeRoot, context.branch, context.baseBranch)
        } catch {
            fail(String(describing: error))
            return false
        }
        guard !inspection.hasUncommittedChanges else {
            _ = runTool(
                ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}"),
                context.worktreeRoot,
                context.authorizedManagedRoot
            )
            fail("The merged worktree changed after publication, so it was preserved for review.")
            return false
        }
        guard validateIdentity(pullRequest, inspection: inspection) else { return false }

        let removal = runTool(
            WorkspaceWorktreeToolCallPlanner.remove(
                WorkspaceWorktreeRemoveRequest(path: context.worktreeRoot.path, force: false)
            ),
            context.projectRoot,
            context.authorizedManagedRoot
        )
        guard removal.ok else {
            fail("Pull request #\(pullRequest.number) is merged, but Git preserved the worktree. Review the failed removal before retrying cleanup.")
            return false
        }
        completeCleanup(context: context, removedWorktree: true)
        return true
    }

    private func authoritativePullRequest(context: PullRequestContext) -> GitBranchPublicationPullRequest? {
        let selector = String(context.link.number)
        let lookup = inspectPullRequest(context.lookupRoot, selector)
        if let warning = lookup.warning {
            fail("GitHub pull request lookup failed: \(warning)")
            return nil
        }
        guard let pullRequest = lookup.pullRequest else {
            fail("GitHub could not find the pull request for this task.")
            return nil
        }
        if pullRequest.number != context.link.number {
            fail("GitHub returned a different pull request than this task owns. Nothing changed.")
            return nil
        }
        return pullRequest
    }

    private func validateIdentity(
        _ pullRequest: GitBranchPublicationPullRequest,
        inspection: GitBranchPublicationInspection
    ) -> Bool {
        guard pullRequest.headBranch == inspection.branch else {
            fail("Pull request #\(pullRequest.number) belongs to '\(pullRequest.headBranch)', not this task's '\(inspection.branch)'.")
            return false
        }
        guard !pullRequest.headCommit.isEmpty,
              pullRequest.headCommit == inspection.headCommit
        else {
            fail("The worktree HEAD does not match pull request #\(pullRequest.number). Publish or refresh the branch before continuing.")
            return false
        }
        return true
    }

    private func landingNotice(for pullRequest: GitBranchPublicationPullRequest) -> String {
        switch pullRequest.lifecycleStatus {
        case .merged:
            return "Pull request #\(pullRequest.number) merged. Its verified worktree is ready for cleanup."
        case .queued:
            return "Pull request #\(pullRequest.number) is queued for merge."
        default:
            return "Pull request #\(pullRequest.number) was submitted for merge and is \(pullRequest.lifecycleStatus.label.lowercased())."
        }
    }

    private func pullRequestContext() -> PullRequestContext? {
        guard lifecycleIsIdle,
              let project = model.selectedProject,
              !project.isRemote,
              let link = model.selectedThread?.pullRequest
        else { return nil }
        let projectRoot = URL(fileURLWithPath: project.path).standardizedFileURL
        let lookupRoot = model.selectedThread?.worktree.flatMap { binding in
            binding.isResolvable ? URL(fileURLWithPath: binding.path).standardizedFileURL : nil
        } ?? projectRoot
        return PullRequestContext(projectRoot: projectRoot, lookupRoot: lookupRoot, link: link)
    }

    private func branchContext() -> BranchContext? {
        guard lifecycleIsIdle,
              let project = model.selectedProject,
              !project.isRemote,
              let binding = model.selectedThread?.worktree,
              binding.location == .worktree,
              binding.isResolvable
        else { return nil }
        let branch = binding.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return nil }
        return BranchContext(
            projectRoot: URL(fileURLWithPath: project.path).standardizedFileURL,
            worktreeRoot: URL(fileURLWithPath: binding.path).standardizedFileURL,
            branch: branch,
            baseBranch: binding.base?.trimmingCharacters(in: .whitespacesAndNewlines),
            authorizedManagedRoot: binding.managedRoot.map {
                URL(fileURLWithPath: $0).standardizedFileURL
            }
        )
    }

    private func cleanupContext() -> CleanupContext? {
        guard lifecycleIsIdle,
              let project = model.selectedProject,
              !project.isRemote,
              let binding = model.selectedThread?.worktree,
              binding.location == .worktree,
              let pullRequest = model.selectedThread?.pullRequest
        else { return nil }

        let branch = binding.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !binding.path.isEmpty, !branch.isEmpty else { return nil }
        let projectRoot = URL(fileURLWithPath: project.path).standardizedFileURL
        let worktreeRoot = URL(fileURLWithPath: binding.path).standardizedFileURL
        let branchContext = BranchContext(
            projectRoot: projectRoot,
            worktreeRoot: worktreeRoot,
            branch: branch,
            baseBranch: binding.base?.trimmingCharacters(in: .whitespacesAndNewlines),
            authorizedManagedRoot: binding.managedRoot.map {
                URL(fileURLWithPath: $0).standardizedFileURL
            }
        )
        return CleanupContext(branchContext: branchContext, pullRequest: PullRequestContext(
            projectRoot: projectRoot,
            lookupRoot: fileExists(worktreeRoot.path) ? worktreeRoot : projectRoot,
            link: pullRequest
        ))
    }

    private var lifecycleIsIdle: Bool {
        !model.composer.isSending
            && !model.terminal.isRunning
            && model.selectedThread?.isArchived == false
    }

    private func completeCleanup(context: CleanupContext, removedWorktree: Bool) {
        guard let threadID = model.root.selectedThreadID else { return }
        model.clearWorktreeBinding(threadID: threadID)
        model.terminal.currentDirectoryPath = context.projectRoot.path
        model.terminal.environmentOverrides = [:]
        model.terminal.removedEnvironmentKeys = []
        model.terminal.resetInputModes()
        model.refreshFileMentionIndex()
        model.appendNotice(
            removedWorktree
                ? "Removed the merged pull request worktree. The task and PR history remain available."
                : "Cleared the already-missing merged worktree binding. The task and PR history remain available."
        )
        model.refreshTopBar()
    }

    private func fail(_ message: String) {
        model.appendNotice(message)
        model.setLastError(message)
    }
}

private extension WorkspaceManagedWorktreePullRequestCoordinator {
    struct PullRequestContext {
        var projectRoot: URL
        var lookupRoot: URL
        var link: PullRequestLink
    }

    struct BranchContext {
        var projectRoot: URL
        var worktreeRoot: URL
        var branch: String
        var baseBranch: String?
        var authorizedManagedRoot: URL?
    }

    struct CleanupContext {
        var branchContext: BranchContext
        var pullRequest: PullRequestContext

        var projectRoot: URL { branchContext.projectRoot }
        var worktreeRoot: URL { branchContext.worktreeRoot }
        var branch: String { branchContext.branch }
        var baseBranch: String? { branchContext.baseBranch }
        var authorizedManagedRoot: URL? { branchContext.authorizedManagedRoot }
    }
}
