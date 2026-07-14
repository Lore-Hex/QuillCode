import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
struct WorkspaceManagedWorktreePublishCoordinator {
    typealias InspectionProvider = (URL, String, String?) throws -> GitBranchPublicationInspection
    typealias ToolRunner = (ToolCall, URL, URL?) -> ToolResult

    let model: QuillCodeWorkspaceModel
    private let inspect: InspectionProvider
    private let runTool: ToolRunner

    init(model: QuillCodeWorkspaceModel) {
        let inspector = GitBranchPublicationInspector()
        self.init(
            model: model,
            inspect: { try inspector.inspect(cwd: $0, expectedBranch: $1, baseBranch: $2) },
            runTool: { call, workspaceRoot, managedRoot in
                model.runToolCall(
                    call,
                    workspaceRoot: workspaceRoot,
                    managedWorktreeRoot: managedRoot
                )
            }
        )
    }

    init(
        model: QuillCodeWorkspaceModel,
        inspect: @escaping InspectionProvider,
        runTool: @escaping ToolRunner
    ) {
        self.model = model
        self.inspect = inspect
        self.runTool = runTool
    }

    func publishSelectedThread() -> Bool {
        guard let context = publicationContext() else { return false }

        let inspection: GitBranchPublicationInspection
        do {
            inspection = try inspect(context.worktreeRoot, context.branch, context.baseBranch)
        } catch {
            fail(String(describing: error))
            return false
        }

        if let warning = inspection.pullRequestLookupWarning {
            model.appendNotice("GitHub pull request lookup warning: \(warning)")
        }
        if inspection.hasUncommittedChanges {
            _ = runTool(
                ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}"),
                context.worktreeRoot,
                context.authorizedManagedRoot
            )
            fail("Review and commit all worktree changes before publishing. Nothing was pushed.")
            return false
        }
        if inspection.commitsBehindUpstream > 0 {
            fail("This branch is behind its upstream. Sync the branch and resolve any divergence before publishing.")
            return false
        }
        if inspection.commitsAheadOfBase == 0, inspection.pullRequest == nil {
            fail("This branch has no committed changes beyond \(inspection.baseBranch ?? "its base"). Commit the task before publishing.")
            return false
        }

        let existingPullRequest = inspection.pullRequest
        if let existingPullRequest {
            model.setSelectedThreadPullRequest(existingPullRequest.durableLink())
        }
        if let pullRequest = existingPullRequest,
           pullRequest.lifecycleStatus.isTerminal {
            let view = runTool(
                ToolCall(
                    name: ToolDefinition.gitPullRequestView.name,
                    argumentsJSON: ToolArguments.json(["selector": String(pullRequest.number)])
                ),
                context.worktreeRoot,
                context.authorizedManagedRoot
            )
            guard view.ok else {
                fail("The branch is published, but its pull request could not be refreshed.")
                return false
            }
            model.appendNotice("Pull request #\(pullRequest.number) is \(pullRequest.lifecycleStatus.label.lowercased()).")
            return true
        }

        if inspection.needsPush {
            let remote = inspection.upstreamRemote ?? "origin"
            let push = runTool(
                ToolCall(
                    name: ToolDefinition.gitPush.name,
                    argumentsJSON: ToolArguments.json([
                        "branch": inspection.branch,
                        "remote": remote,
                        "setUpstream": inspection.upstream == nil
                    ])
                ),
                context.worktreeRoot,
                context.authorizedManagedRoot
            )
            guard push.ok else {
                fail("The branch could not be pushed. Review the failed Git card and try Publish again.")
                return false
            }
        }

        if let pullRequest = existingPullRequest {
            let view = runTool(
                ToolCall(
                    name: ToolDefinition.gitPullRequestView.name,
                    argumentsJSON: ToolArguments.json(["selector": String(pullRequest.number)])
                ),
                context.worktreeRoot,
                context.authorizedManagedRoot
            )
            guard view.ok else {
                fail("The branch was published, but its pull request could not be refreshed.")
                return false
            }
            var publishedLink = pullRequest.durableLink()
            publishedLink.headCommit = inspection.headCommit
            model.setSelectedThreadPullRequest(publishedLink)
            model.appendNotice("Published \(inspection.branch) and refreshed pull request #\(pullRequest.number).")
            return true
        }

        var arguments: [String: Any] = [
            "fill": true,
            "head": inspection.branch
        ]
        if let base = inspection.baseBranch {
            arguments["base"] = base
        }
        let create = runTool(
            ToolCall(
                name: ToolDefinition.gitPullRequestCreate.name,
                argumentsJSON: ToolArguments.json(arguments)
            ),
            context.worktreeRoot,
            context.authorizedManagedRoot
        )
        guard create.ok else {
            fail("The branch was pushed, but GitHub could not create its pull request. Review the failed PR card and retry.")
            return false
        }
        guard let pullRequest = createdPullRequest(
            result: create,
            inspection: inspection
        ) else {
            fail("The pull request opened, but GitHub did not return a recognizable pull request URL. Refresh its status before landing.")
            return false
        }
        model.setSelectedThreadPullRequest(pullRequest)
        model.appendNotice("Published \(inspection.branch) and opened its pull request.")
        return true
    }

    private func createdPullRequest(
        result: ToolResult,
        inspection: GitBranchPublicationInspection
    ) -> PullRequestLink? {
        let candidates = result.artifacts + GitHubPullRequestOutputParser.extractURLs(from: result.stdout)
        guard let match = candidates.lazy.compactMap(pullRequestIdentity).first else { return nil }
        return PullRequestLink(
            number: match.number,
            title: inspection.branch,
            url: match.url,
            status: .open,
            baseBranch: inspection.baseBranch ?? "",
            headBranch: inspection.branch,
            headCommit: inspection.headCommit
        )
    }

    private func pullRequestIdentity(from candidate: String) -> (url: String, number: Int)? {
        guard let url = URL(string: candidate),
              let pullIndex = url.pathComponents.lastIndex(of: "pull"),
              url.pathComponents.indices.contains(pullIndex + 1),
              let number = Int(url.pathComponents[pullIndex + 1]),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.query = nil
        components.fragment = nil
        guard let canonicalURL = components.url?.absoluteString else { return nil }
        return (canonicalURL, number)
    }

    private func publicationContext() -> PublicationContext? {
        guard !model.composer.isSending,
              !model.terminal.isRunning,
              model.selectedThread?.isArchived == false,
              let project = model.selectedProject,
              !project.isRemote,
              let binding = model.selectedThread?.worktree,
              binding.location == .worktree,
              binding.isResolvable
        else { return nil }

        let branch = binding.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return nil }
        return PublicationContext(
            worktreeRoot: URL(fileURLWithPath: binding.path).standardizedFileURL,
            branch: branch,
            baseBranch: binding.base?.trimmingCharacters(in: .whitespacesAndNewlines),
            authorizedManagedRoot: binding.managedRoot.map {
                URL(fileURLWithPath: $0).standardizedFileURL
            }
        )
    }

    private func fail(_ message: String) {
        model.appendNotice(message)
        model.setLastError(message)
    }
}

private extension WorkspaceManagedWorktreePublishCoordinator {
    struct PublicationContext {
        let worktreeRoot: URL
        let branch: String
        let baseBranch: String?
        let authorizedManagedRoot: URL?
    }
}
