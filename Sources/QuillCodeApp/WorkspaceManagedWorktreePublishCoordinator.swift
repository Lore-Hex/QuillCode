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
        if inspection.commitsAheadOfBase == 0, inspection.openPullRequest == nil {
            fail("This branch has no committed changes beyond \(inspection.baseBranch ?? "its base"). Commit the task before publishing.")
            return false
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

        if let pullRequest = inspection.openPullRequest {
            let view = runTool(
                ToolCall(
                    name: ToolDefinition.gitPullRequestView.name,
                    argumentsJSON: ToolArguments.json(["selector": inspection.branch])
                ),
                context.worktreeRoot,
                context.authorizedManagedRoot
            )
            guard view.ok else {
                fail("The branch was published, but its pull request could not be refreshed.")
                return false
            }
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
        model.appendNotice("Published \(inspection.branch) and opened its pull request.")
        return true
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
