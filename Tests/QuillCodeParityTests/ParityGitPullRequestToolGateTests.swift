import XCTest

final class ParityGitPullRequestToolGateTests: QuillCodeParityTestCase {
    func testGitToolDefinitionsLiveOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let localDefinitionsText = try Self.toolsSourceText(named: "GitLocalToolDefinitions.swift")
        let pullRequestOverviewText = try Self.toolsSourceText(named: "GitPullRequestOverviewToolDefinitions.swift")
        let pullRequestMetadataText = try Self.toolsSourceText(named: "GitPullRequestMetadataToolDefinitions.swift")
        let pullRequestReviewText = try Self.toolsSourceText(named: "GitPullRequestReviewToolDefinitions.swift")
        let pullRequestMergeText = try Self.toolsSourceText(named: "GitPullRequestMergeToolDefinitions.swift")
        let worktreeDefinitionsText = try Self.toolsSourceText(named: "GitWorktreeToolDefinitions.swift")
        let schemaText = try Self.toolsSourceText(named: "GitToolParameterSchema.swift")
        let definitionFactoryText = try Self.toolsSourceText(named: "GitToolDefinitionFactory.swift")
        let pullRequestFactoryText = try Self.toolsSourceText(named: "GitPullRequestDefinitionFactory.swift")
        let definitionTexts = [
            localDefinitionsText,
            pullRequestOverviewText,
            pullRequestMetadataText,
            pullRequestReviewText,
            pullRequestMergeText,
            worktreeDefinitionsText
        ].joined(separator: "\n")

        Self.assertSource(localDefinitionsText, contains: "static let gitStatus")
        Self.assertSource(localDefinitionsText, contains: "static let gitPush")
        XCTAssertTrue(
            pullRequestOverviewText.contains("static let gitPullRequestView"),
            "PR overview/read definitions should live in the overview catalog."
        )
        XCTAssertTrue(
            pullRequestMetadataText.contains("static let gitPullRequestReviewers"),
            "PR metadata mutations should live in the metadata catalog."
        )
        XCTAssertTrue(
            pullRequestReviewText.contains("static let gitPullRequestReviewComment"),
            "PR review-thread definitions should live in the review catalog."
        )
        XCTAssertTrue(
            pullRequestMergeText.contains("static let gitPullRequestMerge"),
            "PR merge definitions should live in the merge catalog."
        )
        XCTAssertTrue(
            worktreeDefinitionsText.contains("static let gitWorktreeRemove"),
            "Worktree definitions should live in the worktree catalog."
        )
        XCTAssertTrue(
            worktreeDefinitionsText.contains("static let gitWorktreePrune"),
            "Worktree cleanup definitions should remain available from the worktree catalog."
        )
        Self.assertSource(schemaText, contains: "enum GitToolParameterSchema")
        Self.assertSource(schemaText, contains: "JSONEncoder()")
        XCTAssertTrue(
            definitionFactoryText.contains("enum GitToolDefinitionFactory"),
            "Shared local-host ToolDefinition construction should live in a focused factory."
        )
        XCTAssertTrue(
            pullRequestFactoryText.contains("enum GitPullRequestDefinitionFactory"),
            "Shared PR selector schema construction should live in a focused PR factory."
        )
        XCTAssertFalse(
            definitionTexts.contains(#"parametersJSON: #"{"#),
            "Git definitions should not reintroduce hand-written JSON schema strings."
        )
        Self.assertSource(executorText, excludes: "public extension ToolDefinition")
        Self.assertSource(executorText, excludes: "parametersJSON")
    }

    func testGitHubPullRequestMetadataResolutionStaysFocused() throws {
        let reviewExecutorText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutorReviewCommands.swift")
        let resolverText = try Self.toolsSourceText(named: "GitHubPullRequestMetadataResolver.swift")
        let resolverTests = try Self.toolsTestSourceText(named: "GitHubPullRequestMetadataResolverTests.swift")

        Self.assertSource(resolverText, contains: "struct GitHubPullRequestMetadataResolver")
        Self.assertSource(resolverText, contains: "struct GitHubPullRequestMetadata")
        Self.assertSource(resolverText, contains: "struct GitHubRepositoryMetadata")
        Self.assertSource(resolverText, contains: "func pullRequest(selector: String?, cwd: URL)")
        Self.assertSource(resolverText, contains: "func repository(cwd: URL)")
        Self.assertSource(resolverText, contains: "JSONDecoder().decode")
        Self.assertSource(reviewExecutorText, contains: "metadataResolver.pullRequest")
        Self.assertSource(reviewExecutorText, contains: "metadataResolver.repository")
        Self.assertSource(resolverTests, contains: "testResolverUsesGitHubCLIAndDecodesMetadata")
        Self.assertSource(resolverTests, contains: "testResolverRejectsInvalidPullRequestMetadata")
        Self.assertSource(resolverTests, contains: "testResolverRejectsInvalidRepositoryMetadata")
        Self.assertSource(reviewExecutorText, excludes: "struct PullRequestMetadata")
        Self.assertSource(reviewExecutorText, excludes: "struct RepositoryMetadata")
        Self.assertSource(reviewExecutorText, excludes: "func resolvePullRequest")
        Self.assertSource(reviewExecutorText, excludes: "func resolveRepository")
        Self.assertSource(reviewExecutorText, excludes: "JSONDecoder().decode")
    }

    func testGitHubPullRequestExecutorDelegatesCommandBuilding() throws {
        let executorText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutor.swift")
        let baseExecutorText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutorBaseCommands.swift")
        let editExecutorText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutorEditCommands.swift")
        let reviewExecutorText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutorReviewCommands.swift")
        let mergeExecutorText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutorMergeCommands.swift")
        let baseBuilderText = try Self.toolsSourceText(named: "GitHubPullRequestBaseCommandBuilder.swift")
        let editBuilderText = try Self.toolsSourceText(named: "GitHubPullRequestEditCommandBuilder.swift")
        let reviewBuilderText = try Self.toolsSourceText(named: "GitHubPullRequestReviewCommandBuilder.swift")
        let mergeBuilderText = try Self.toolsSourceText(named: "GitHubPullRequestMergeCommandBuilder.swift")
        let supportText = try Self.toolsSourceText(named: "GitHubPullRequestCommandSupport.swift")

        Self.assertSource(baseBuilderText, contains: "enum GitHubPullRequestBaseCommandBuilder")
        Self.assertSource(editBuilderText, contains: "enum GitHubPullRequestEditCommandBuilder")
        Self.assertSource(reviewBuilderText, contains: "enum GitHubPullRequestReviewCommandBuilder")
        Self.assertSource(mergeBuilderText, contains: "enum GitHubPullRequestMergeCommandBuilder")
        Self.assertSource(supportText, contains: "static func appendSelector")
        Self.assertSource(supportText, contains: "static func addURLArtifacts")
        Self.assertSource(supportText, contains: "static func repositoryOwnerAndName")
        Self.assertSource(baseExecutorText, contains: "GitHubPullRequestBaseCommandBuilder.create")
        Self.assertSource(editExecutorText, contains: "GitHubPullRequestEditCommandBuilder.reviewers")
        Self.assertSource(reviewExecutorText, contains: "GitHubPullRequestReviewCommandBuilder.reviewComment")
        Self.assertSource(mergeExecutorText, contains: "GitHubPullRequestMergeCommandBuilder.merge")
        Self.assertSource(executorText, contains: "GitHubPullRequestCommandSupport.addURLArtifacts")
        XCTAssertFalse(executorText.contains(#"["pr", "create"]"#), "GitHub PR executor should not own create CLI assembly.")
        XCTAssertFalse(executorText.contains(#"["pr", "edit"]"#), "GitHub PR executor should not own edit CLI assembly.")
        XCTAssertFalse(executorText.contains(#"["api", "graphql"]"#), "GitHub PR executor should not own GraphQL CLI assembly.")
        Self.assertSource(executorText, excludes: "GitInputValidator.safeRelativePath")
        Self.assertSource(executorText, excludes: "GitHubPullRequestInputValidator.safeMergeFlag")
        Self.assertSource(executorText, excludes: "reviewThreadMutation")
        Self.assertSource(executorText, excludes: "repositoryOwnerAndName")
    }

    func testToolRouterDelegatesGitToolCallDispatch() throws {
        let routerText = try Self.toolsSourceText(named: "ToolRouter.swift")
        let dispatcherText = try Self.toolsSourceText(named: "GitToolCallDispatcher.swift")

        Self.assertSource(dispatcherText, contains: "struct GitToolCallDispatcher")
        Self.assertSource(dispatcherText, contains: "static let definitions")
        Self.assertSource(dispatcherText, contains: "func execute(")
        Self.assertSource(routerText, contains: "GitToolCallDispatcher.definitions")
        Self.assertSource(routerText, contains: "GitToolCallDispatcher.handles")
        Self.assertSource(routerText, excludes: "ToolDefinition.gitStatus.name")
        Self.assertSource(routerText, excludes: "ToolDefinition.gitPullRequestCreate.name")
        Self.assertSource(routerText, excludes: "ToolDefinition.gitWorktreeCreate.name")
        Self.assertSource(routerText, excludes: "git.createPullRequest")
        Self.assertSource(routerText, excludes: "git.createWorktree")
    }

    func testGitHubPullRequestToolCoverageLivesOutsideMixedToolSuite() throws {
        let baseTestsText = try Self.toolsTestSourceText(named: "GitHubPullRequestBaseToolExecutorTests.swift")
        let editTestsText = try Self.toolsTestSourceText(named: "GitHubPullRequestEditToolExecutorTests.swift")
        let reviewTestsText = try Self.toolsTestSourceText(named: "GitHubPullRequestReviewToolExecutorTests.swift")
        let mergeTestsText = try Self.toolsTestSourceText(named: "GitHubPullRequestMergeToolExecutorTests.swift")
        let routerTestsText = try Self.toolsTestSourceText(named: "GitHubPullRequestToolRouterTests.swift")
        let supportText = try Self.toolsTestSourceText(named: "GitHubPullRequestTestSupport.swift")

        XCTAssertTrue(
            baseTestsText.contains("final class GitHubPullRequestBaseToolExecutorTests"),
            "GitHub PR create/view/checks/diff/checkout coverage should live in a focused suite."
        )
        XCTAssertTrue(
            editTestsText.contains("final class GitHubPullRequestEditToolExecutorTests"),
            "GitHub PR reviewer/label/comment coverage should live in a focused suite."
        )
        XCTAssertTrue(
            reviewTestsText.contains("final class GitHubPullRequestReviewToolExecutorTests"),
            "GitHub PR review-comment/thread coverage should live in a focused suite."
        )
        XCTAssertTrue(
            mergeTestsText.contains("final class GitHubPullRequestMergeToolExecutorTests"),
            "GitHub PR merge and helper coverage should live in a focused suite."
        )
        XCTAssertTrue(
            routerTestsText.contains("final class GitHubPullRequestToolRouterTests"),
            "GitHub PR tool-router coverage should live in a focused suite."
        )
        XCTAssertTrue(
            supportText.contains("struct GitHubPullRequestCLIFixture"),
            "GitHub PR tests should share the fake gh fixture instead of repeating setup in each test."
        )
        XCTAssertTrue(
            baseTestsText.contains("testCreatePullRequestUsesGitHubCLIArguments"),
            "PR creation coverage should stay beside the GitHub PR executor tests."
        )
        XCTAssertTrue(
            routerTestsText.contains("testToolRouterRoutesPullRequestReviewTools"),
            "PR tool-router coverage should stay beside the PR executor tests."
        )
    }

    func testGitToolCoverageLivesOutsideMixedToolSuite() throws {
        let localTestsText = try Self.toolsTestSourceText(named: "GitLocalToolExecutorTests.swift")
        let patchTestsText = try Self.toolsTestSourceText(named: "GitPatchToolExecutorTests.swift")
        let worktreeTestsText = try Self.toolsTestSourceText(named: "GitWorktreeToolExecutorTests.swift")
        let routerTestsText = try Self.toolsTestSourceText(named: "GitToolRouterTests.swift")

        XCTAssertTrue(
            localTestsText.contains("final class GitLocalToolExecutorTests"),
            "Local git stage, restore, commit, push, and input validation coverage should live in a focused suite."
        )
        XCTAssertTrue(
            patchTestsText.contains("final class GitPatchToolExecutorTests"),
            "Git hunk stage/restore coverage should live in a focused suite."
        )
        XCTAssertTrue(
            worktreeTestsText.contains("final class GitWorktreeToolExecutorTests"),
            "Git worktree lifecycle coverage should live in a focused suite."
        )
        XCTAssertTrue(
            routerTestsText.contains("final class GitToolRouterTests"),
            "Git dispatcher/router coverage should live in a focused suite."
        )
        XCTAssertTrue(
            localTestsText.contains("testPushPushesCurrentBranchToNamedRemote"),
            "Local git push coverage should stay beside local git executor tests."
        )
        XCTAssertTrue(
            patchTestsText.contains("testStageHunkStagesSelectedPatch"),
            "Hunk staging coverage should stay beside git patch executor tests."
        )
        XCTAssertTrue(
            worktreeTestsText.contains("testCreateListOpenAndRemoveSibling"),
            "Worktree lifecycle coverage should stay beside git worktree executor tests."
        )
        XCTAssertTrue(
            routerTestsText.contains("testToolRouterExposesGitDefinitions"),
            "Git definition exposure coverage should stay beside git router tests."
        )
    }

    func testGitLocalExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let localText = try Self.toolsSourceText(named: "GitLocalToolExecutor.swift")

        Self.assertSource(localText, contains: "public struct GitLocalToolExecutor")
        Self.assertSource(localText, contains: "func status(")
        Self.assertSource(localText, contains: "func diff(")
        Self.assertSource(localText, contains: "func stage(")
        Self.assertSource(localText, contains: "func restore(")
        Self.assertSource(localText, contains: "func commit(")
        Self.assertSource(localText, contains: "func push(")
        Self.assertSource(localText, contains: "GitInputValidator.safeRelativePath")
        Self.assertSource(executorText, contains: "private let local: GitLocalToolExecutor")
        XCTAssertFalse(executorText.contains(#"["add", "--""#), "GitToolExecutor should not build git add arguments inline.")
        XCTAssertFalse(executorText.contains(#"["restore"]"#), "GitToolExecutor should not build git restore arguments inline.")
        XCTAssertFalse(executorText.contains(#"["commit", "-m""#), "GitToolExecutor should not build git commit arguments inline.")
        XCTAssertFalse(executorText.contains(#"["push"]"#), "GitToolExecutor should not build git push arguments inline.")
        Self.assertSource(executorText, excludes: "currentBranchName")
    }

    func testGitHubPullRequestExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let pullRequestText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutor.swift")
        let pullRequestBaseExecutorText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutorBaseCommands.swift")
        let pullRequestBaseBuilderText = try Self.toolsSourceText(named: "GitHubPullRequestBaseCommandBuilder.swift")
        let pullRequestMergeBuilderText = try Self.toolsSourceText(named: "GitHubPullRequestMergeCommandBuilder.swift")
        let inputValidatorText = try Self.toolsSourceText(named: "GitHubPullRequestInputValidator.swift")
        let outputParserText = try Self.toolsSourceText(named: "GitHubPullRequestOutputParser.swift")
        let commandSupportText = try Self.toolsSourceText(named: "GitHubPullRequestCommandSupport.swift")
        let processRunnerText = try Self.toolsSourceText(named: "GitProcessRunner.swift")

        Self.assertSource(pullRequestText, contains: "public struct GitHubPullRequestToolExecutor")
        Self.assertSource(pullRequestBaseExecutorText, contains: "func createPullRequest")
        Self.assertSource(pullRequestBaseBuilderText, contains: "static func create")
        Self.assertSource(pullRequestMergeBuilderText, contains: "static func merge(")
        Self.assertSource(inputValidatorText, contains: "public enum GitHubPullRequestInputValidator")
        Self.assertSource(inputValidatorText, contains: "static func safeSelector")
        Self.assertSource(inputValidatorText, contains: "static func safeReviewers")
        Self.assertSource(outputParserText, contains: "public enum GitHubPullRequestOutputParser")
        Self.assertSource(outputParserText, contains: "static func extractURLs")
        Self.assertSource(commandSupportText, contains: "GitHubPullRequestInputValidator.safeSelector")
        Self.assertSource(commandSupportText, contains: "GitHubPullRequestOutputParser.extractURLs")
        Self.assertSource(pullRequestText, contains: "GitHubPullRequestCommandSupport.addURLArtifacts")
        Self.assertSource(processRunnerText, contains: "public struct GitProcessRunner")
        Self.assertSource(processRunnerText, contains: "func runGitHub")
        Self.assertSource(executorText, contains: "private let pullRequests: GitHubPullRequestToolExecutor")
        Self.assertSource(executorText, excludes: "func runGitHub")
        Self.assertSource(executorText, excludes: "Process()")
        XCTAssertFalse(executorText.contains(#"["pr", "create"]"#), "GitToolExecutor should not build GitHub PR command arguments inline.")
        Self.assertSource(executorText, excludes: "addURLArtifacts")
        Self.assertSource(pullRequestText, excludes: "static func safeSelector")
        Self.assertSource(pullRequestText, excludes: "static func extractURLs")
    }

    func testGitWorktreeExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let worktreeText = try Self.toolsSourceText(named: "GitWorktreeToolExecutor.swift")

        Self.assertSource(worktreeText, contains: "public struct GitWorktreeToolExecutor")
        Self.assertSource(worktreeText, contains: "func list(")
        Self.assertSource(worktreeText, contains: "func create(")
        Self.assertSource(worktreeText, contains: "func open(")
        Self.assertSource(worktreeText, contains: "func remove(")
        Self.assertSource(worktreeText, contains: "func prune(")
        Self.assertSource(worktreeText, contains: "static func safePath")
        Self.assertSource(worktreeText, contains: "registeredPaths")
        Self.assertSource(executorText, contains: "private let worktrees: GitWorktreeToolExecutor")
        XCTAssertFalse(executorText.contains(#"["worktree", "add"]"#), "GitToolExecutor should not build git worktree add arguments inline.")
        XCTAssertFalse(executorText.contains(#"["worktree", "remove"]"#), "GitToolExecutor should not build git worktree remove arguments inline.")
        Self.assertSource(executorText, excludes: "safeWorktreePath")
        Self.assertSource(executorText, excludes: "registeredWorktreePaths")
    }

    func testGitPatchExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let patchText = try Self.toolsSourceText(named: "GitPatchToolExecutor.swift")
        let remoteGitHunkBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHunkCommandBuilder.swift")
        let remoteGitPlannerText = try Self.appSourceText(named: "WorkspaceRemoteGitToolRequestPlanner.swift")

        Self.assertSource(patchText, contains: "public struct GitPatchToolExecutor")
        Self.assertSource(patchText, contains: "func stageHunk(")
        Self.assertSource(patchText, contains: "func restoreHunk(")
        Self.assertSource(patchText, contains: "static func mismatchedPatchPath")
        Self.assertSource(executorText, contains: "private let patches: GitPatchToolExecutor")
        Self.assertSource(remoteGitHunkBuilderText, contains: "GitPatchToolExecutor.mismatchedPatchPath")
        Self.assertSource(executorText, excludes: "private func applyHunk")
        Self.assertSource(executorText, excludes: "mismatchedPatchPath")
        Self.assertSource(executorText, excludes: "temporaryPatchFailed")
        Self.assertSource(executorText, excludes: "pathsInDiffMetadataLine")
        Self.assertSource(remoteGitPlannerText, excludes: "GitPatchToolExecutor.mismatchedPatchPath")
    }

    func testGitSharedInputValidationLivesOutsideGitFacade() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let localText = try Self.toolsSourceText(named: "GitLocalToolExecutor.swift")
        let validatorText = try Self.toolsSourceText(named: "GitInputValidator.swift")
        let pullRequestText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutor.swift")
        let pullRequestBaseBuilderText = try Self.toolsSourceText(named: "GitHubPullRequestBaseCommandBuilder.swift")
        let worktreeText = try Self.toolsSourceText(named: "GitWorktreeToolExecutor.swift")
        let remoteGitPlannerText = try Self.appSourceText(named: "WorkspaceRemoteGitToolRequestPlanner.swift")
        let remoteGitPushBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitPushCommandBuilder.swift")

        Self.assertSource(validatorText, contains: "public enum GitInputValidator")
        Self.assertSource(validatorText, contains: "static let safeNameCharacters")
        Self.assertSource(validatorText, contains: "static func trimmedNonEmpty")
        Self.assertSource(validatorText, contains: "static func safeName")
        Self.assertSource(validatorText, contains: "static func safeRelativePath")
        Self.assertSource(localText, contains: "GitInputValidator.safeRelativePath")
        Self.assertSource(pullRequestBaseBuilderText, contains: "GitInputValidator.safeName")
        Self.assertSource(worktreeText, contains: "GitInputValidator.safeName")
        Self.assertSource(remoteGitPushBuilderText, contains: "GitInputValidator.safeName")
        Self.assertSource(remoteGitPushBuilderText, contains: "GitInputValidator.safeNameCharacters")
        Self.assertSource(executorText, excludes: "GitInputValidator.safeRelativePath")
        Self.assertSource(pullRequestText, excludes: "GitToolExecutor.safeGitName")
        Self.assertSource(pullRequestText, excludes: "GitToolExecutor.trimmedNonEmpty")
        Self.assertSource(worktreeText, excludes: "GitToolExecutor.safeGitName")
        Self.assertSource(worktreeText, excludes: "GitToolExecutor.trimmedNonEmpty")
        Self.assertSource(remoteGitPlannerText, excludes: "GitToolExecutor.safeGitName")
        Self.assertSource(remoteGitPlannerText, excludes: "GitToolExecutor.trimmedNonEmpty")
        Self.assertSource(remoteGitPlannerText, excludes: "GitInputValidator.safeName")
    }

    func testPullRequestReviewThreadParityMatrixMatchesImplementedTools() throws {
        let matrix = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")

        XCTAssertTrue(
            matrix.contains("inline comment replies via `gh api`"),
            "The parity matrix should mention implemented PR review-reply execution."
        )
        XCTAssertTrue(
            matrix.contains("review-thread listing plus resolve/unresolve via `gh api graphql`"),
            "The parity matrix should mention implemented PR review-thread listing and resolution execution."
        )
        XCTAssertFalse(
            matrix.contains("inline comment reply/resolution workflows pending"),
            "Implemented PR review reply/thread tools should not be described as pending."
        )
        XCTAssertFalse(
            matrix.contains("reply, and resolution workflows pending"),
            "Implemented PR review reply/thread tools should not be described as pending in the review pane row."
        )
    }
}
