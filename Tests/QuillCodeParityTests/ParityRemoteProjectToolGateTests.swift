import XCTest

final class ParityRemoteProjectToolGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesRemoteProjectToolExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceRemoteProjectToolExecutor.swift")
        let commandPlanText = try Self.appSourceText(named: "WorkspaceRemoteProjectCommandPlan.swift")
        let toolCatalogText = try Self.appSourceText(named: "WorkspaceRemoteProjectToolCatalog.swift")
        let executionContextText = try Self.appSourceText(named: "WorkspaceRemoteProjectToolExecutionContext.swift")
        let fileExecutorText = try Self.appSourceText(named: "WorkspaceRemoteProjectFileToolExecutor.swift")
        let gitPlannerText = try Self.appSourceText(named: "WorkspaceRemoteGitToolRequestPlanner.swift")
        let basicBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitBasicCommandBuilder.swift")
        let hunkBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHunkCommandBuilder.swift")
        let pushBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitPushCommandBuilder.swift")
        let pullRequestBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHubPullRequestCommandBuilder.swift")
        let pullRequestBaseBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHubPullRequestBaseCommandBuilder.swift")
        let pullRequestEditBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHubPullRequestEditCommandBuilder.swift")
        let pullRequestReviewBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHubPullRequestReviewCommandBuilder.swift")
        let pullRequestMergeBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHubPullRequestMergeCommandBuilder.swift")
        let pullRequestSupportText = try Self.appSourceText(named: "WorkspaceRemoteGitHubPullRequestCommandSupport.swift")
        let remoteShellFormatterText = try Self.appSourceText(named: "WorkspaceRemoteShellCommandFormatter.swift")
        let worktreeBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitWorktreeCommandBuilder.swift")
        let remotePathText = try Self.appSourceText(named: "WorkspaceRemoteProjectPath.swift")
        let appServerProtocolText = try Self.toolsSourceText(named: "SSHRemoteAppServerProtocol.swift")
        let appServerClientText = try Self.toolsSourceText(named: "SSHRemoteAppServerClient.swift")
        let appServerPoolText = try Self.toolsSourceText(named: "SSHRemoteAppServerPool.swift")
        let appServerTestsText = try Self.toolsTestSourceText(named: "SSHRemoteAppServerPoolTests.swift")
        let modelAgentSessionText = try Self.appSourceText(named: "WorkspaceModelAgentSession.swift")

        Self.assertSource(executorText, contains: "struct WorkspaceRemoteProjectToolExecutor")
        Self.assertSource(executorText, contains: "static let toolDefinitions")
        Self.assertSource(executorText, contains: "static let gitToolNames")
        Self.assertSource(executorText, contains: "static func executionOverride")
        Self.assertSource(executorText, contains: "static func execute")
        Self.assertSource(toolCatalogText, containsAll: [
            "enum WorkspaceRemoteProjectToolCatalog",
            "static let toolDefinitions",
            "static let gitToolNames"
        ])
        Self.assertSource(executionContextText, containsAll: [
            "struct WorkspaceRemoteProjectToolExecutionContext",
            "func run(",
            "func run(_ plan: WorkspaceRemoteProjectCommandPlan)",
            "SSH Remote project is missing a usable host."
        ])
        Self.assertSource(commandPlanText, containsAll: [
            "struct WorkspaceRemoteProjectCommandPlan",
            "timeoutSeconds",
            "func finalize"
        ])
        Self.assertSource(fileExecutorText, containsAll: [
            "enum WorkspaceRemoteProjectFileToolExecutor",
            "WorkspaceRemoteProjectPath.relativePath",
            "WorkspaceRemoteProjectPath.artifactPath"
        ])
        Self.assertSource(gitPlannerText, contains: "struct WorkspaceRemoteGitToolRequest")
        Self.assertSource(gitPlannerText, contains: "enum WorkspaceRemoteGitToolRequestPlanner")
        Self.assertSource(basicBuilderText, contains: "enum WorkspaceRemoteGitBasicCommandBuilder")
        Self.assertSource(basicBuilderText, contains: "WorkspaceRemoteProjectPath.relativePath")
        Self.assertSource(basicBuilderText, contains: "GitToolError.emptyCommitMessage")
        Self.assertSource(hunkBuilderText, contains: "enum WorkspaceRemoteGitHunkCommandBuilder")
        Self.assertSource(hunkBuilderText, contains: "GitPatchToolExecutor.mismatchedPatchPath")
        Self.assertSource(pushBuilderText, contains: "enum WorkspaceRemoteGitPushCommandBuilder")
        Self.assertSource(pushBuilderText, contains: "GitInputValidator.safeName")
        Self.assertSource(pullRequestBuilderText, contains: "enum WorkspaceRemoteGitHubPullRequestCommandBuilder")
        Self.assertSource(pullRequestBuilderText, contains: "WorkspaceRemoteGitHubPullRequestBaseCommandBuilder.command")
        Self.assertSource(pullRequestBuilderText, contains: "WorkspaceRemoteGitHubPullRequestEditCommandBuilder.command")
        Self.assertSource(pullRequestBuilderText, contains: "WorkspaceRemoteGitHubPullRequestReviewCommandBuilder.command")
        Self.assertSource(pullRequestBuilderText, contains: "WorkspaceRemoteGitHubPullRequestMergeCommandBuilder.command")
        Self.assertSource(pullRequestBuilderText, excludes: "gh api")
        Self.assertSource(pullRequestBuilderText, excludes: "GitInputValidator.trimmedNonEmpty")
        Self.assertSource(pullRequestBuilderText, excludes: "args.")
        Self.assertSource(pullRequestBaseBuilderText, contains: "ToolDefinition.gitPullRequestCreate.name")
        Self.assertSource(pullRequestBaseBuilderText, contains: "WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector")
        Self.assertSource(pullRequestEditBuilderText, contains: "GitHubPullRequestInputValidator.safeReviewers")
        Self.assertSource(pullRequestReviewBuilderText, contains: "WorkspaceRemoteProjectPath.relativePath")
        Self.assertSource(pullRequestReviewBuilderText, contains: "GitHubPullRequestReviewThreadsQuery.graphql")
        Self.assertSource(pullRequestMergeBuilderText, contains: "GitHubPullRequestInputValidator.safeMergeFlag")
        Self.assertSource(pullRequestSupportText, contains: "GitHubPullRequestInputValidator.safeSelector")
        Self.assertSource(pullRequestSupportText, contains: "WorkspaceRemoteShellCommandFormatter.command")
        Self.assertSource(remoteShellFormatterText, contains: "WorkspaceTerminalSessionAdapter.shellSingleQuoted")
        Self.assertSource(worktreeBuilderText, contains: "enum WorkspaceRemoteGitWorktreeCommandBuilder")
        Self.assertSource(worktreeBuilderText, contains: "WorkspaceRemoteProjectPath.worktreePath")
        Self.assertSource(remotePathText, contains: "enum WorkspaceRemoteProjectPath")
        Self.assertSource(executorText, contains: "WorkspaceRemoteGitToolRequestPlanner.request")
        Self.assertSource(gitPlannerText, contains: "WorkspaceRemoteGitBasicCommandBuilder.command")
        Self.assertSource(gitPlannerText, contains: "WorkspaceRemoteGitHunkCommandBuilder.command")
        Self.assertSource(gitPlannerText, contains: "WorkspaceRemoteGitPushCommandBuilder.command")
        Self.assertSource(gitPlannerText, contains: "WorkspaceRemoteGitHubPullRequestCommandBuilder.command")
        Self.assertSource(gitPlannerText, contains: "WorkspaceRemoteGitWorktreeCommandBuilder.plan")
        Self.assertSource(fileExecutorText, contains: "WorkspaceRemoteProjectPath.relativePath")
        Self.assertSource(builderText, contains: "WorkspaceRemoteProjectToolExecutor.toolDefinitions")
        Self.assertSource(builderText, contains: "WorkspaceRemoteProjectToolExecutor.executionOverride")
        Self.assertSource(builderText, contains: "appServer: sshRemoteAppServer")
        Self.assertSource(modelAgentSessionText, contains: "sshRemoteAppServer: sshRemoteAppServer")
        Self.assertSource(appServerProtocolText, containsAll: [
            "protocol SSHRemoteAppServerExecuting",
            "case unavailableBeforeExecution",
            "case executionStateUnknown"
        ])
        Self.assertSource(appServerClientText, containsAll: [
            "app-server --stdio",
            "command/exec",
            "requestMayHaveStarted",
            ".executionStateUnknown"
        ])
        Self.assertSource(appServerClientText, excludes: "retry")
        Self.assertSource(appServerPoolText, containsAll: [
            "actor SSHRemoteAppServerPool",
            "clients: [ConnectionKey: SSHRemoteAppServerClient]",
            "withTaskCancellationHandler",
            "disconnectAll"
        ])
        Self.assertSource(executorText, containsAll: [
            "case .unavailableBeforeExecution:",
            "case .executionStateUnknown(let detail):",
            "did not retry it to avoid duplicate changes",
            "EnvironmentOverridePolicy.validateOverrides",
            "Shell stdin must be at most 1048576 UTF-8 bytes.",
            "Shell timeoutSeconds must be between 1 and 1800."
        ])
        Self.assertSource(appServerTestsText, containsAll: [
            "testExecutesCommandsThroughOnePersistentRemoteAppServer",
            "testReportsUnavailableBeforeExecutionWhenRemoteBinaryCannotStart",
            "testDoesNotClassifyDisconnectAfterDispatchAsSafeToRetry",
            "testDefinitiveRPCRejectionDoesNotBecomeUnknownOrBreakTheSession",
            "testCancellationDropsUncertainSessionBeforeNextCommand"
        ])
        Self.assertSource(toolRunsText, contains: "WorkspaceToolRunCoordinator")
        Self.assertSource(try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift"), contains: "WorkspaceToolCallExecutorFactory.executor")
        Self.assertSource(try Self.appSourceText(named: "WorkspaceToolCallExecutorFactory.swift"), contains: "WorkspaceToolCallExecutor(")
        Self.assertSource(modelText, excludes: "func workspaceToolCallExecutor")
        Self.assertSource(try Self.appSourceText(named: "WorkspaceToolCallExecutor.swift"), contains: "WorkspaceRemoteProjectToolExecutor.execute")
        Self.assertSource(modelText, excludes: "WorkspaceRemoteProjectToolExecutor.toolDefinitions")
        Self.assertSource(modelText, excludes: "WorkspaceRemoteProjectToolExecutor.executionOverride")
        Self.assertSource(executorText, excludes: "private static func remoteGitPullRequestCommand")
        Self.assertSource(gitPlannerText, excludes: "git status --short --branch")
        Self.assertSource(gitPlannerText, excludes: "git add --")
        Self.assertSource(gitPlannerText, excludes: "git commit -m")
        Self.assertSource(gitPlannerText, excludes: "private static func remoteGitPullRequest")
        XCTAssertFalse(gitPlannerText.contains(#"["gh", "pr""#), "Generic remote git planning should not assemble gh pr arguments inline.")
        Self.assertSource(executorText, excludes: "private static func remoteGitWorktreePath")
        Self.assertSource(gitPlannerText, excludes: "private static func remoteGitHunk")
        Self.assertSource(gitPlannerText, excludes: "quillcode-hunk")
        Self.assertSource(gitPlannerText, excludes: "private static func remoteGitPush")
        Self.assertSource(gitPlannerText, excludes: "branch=$(git branch --show-current)")
        Self.assertSource(gitPlannerText, excludes: "private static func remoteGitWorktree")
        XCTAssertFalse(gitPlannerText.contains(#"["git", "worktree""#), "Generic remote git planning should not assemble git worktree arguments inline.")
        Self.assertSource(modelText, excludes: "executeRemoteGitToolCall")
        Self.assertSource(modelText, excludes: "executeRemoteShellToolCall")
        Self.assertSource(modelText, excludes: "remoteProjectGitToolNames")
        Self.assertSource(modelText, excludes: "remoteProjectRelativePath")
    }

}
