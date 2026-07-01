import XCTest

final class ParityToolGateTests: QuillCodeParityTestCase {
    func testToolArgumentJSONSerializationLivesInCore() throws {
        let argumentsText = try Self.coreSourceText(named: "Arguments.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let pullRequestSlashText = try Self.appSourceText(named: "SlashPullRequestCommandParser.swift")
        let shellPlannerText = try Self.appSourceText(named: "WorkspaceShellToolCallPlanner.swift")
        let worktreePlannerText = try Self.appSourceText(named: "WorkspaceWorktreeToolCallPlanner.swift")
        let reviewPlannerText = try Self.appSourceText(named: "WorkspaceReviewActionToolCallPlanner.swift")

        XCTAssertTrue(
            argumentsText.contains("public static func json(_ values: [String: Any])"),
            "Mixed tool argument JSON serialization should live in QuillCodeCore."
        )
        XCTAssertTrue(
            pullRequestSlashText.contains("ToolArguments.json("),
            "Slash PR parser should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            shellPlannerText.contains("ToolArguments.json("),
            "Shell tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            worktreePlannerText.contains("ToolArguments.json("),
            "Worktree tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            reviewPlannerText.contains("ToolArguments.json("),
            "Review action tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertFalse(
            modelText.contains("private func toolArgumentsJSON"),
            "WorkspaceModel should not own ad hoc JSON serialization."
        )
        XCTAssertFalse(
            modelText.contains("JSONSerialization"),
            "WorkspaceModel should not own JSON serialization."
        )
        XCTAssertFalse(
            slashText.contains("private static func json(_ values: [String: Any])"),
            "SlashCommand should not own ad hoc JSON serialization."
        )
    }

    func testSlashCommandCatalogLivesOutsideParser() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let pullRequestSlashText = try Self.appSourceText(named: "SlashPullRequestCommandParser.swift")
        let catalogText = try Self.appSourceText(named: "SlashCommandCatalog.swift")

        XCTAssertTrue(catalogText.contains("public struct SlashCommandSuggestionSurface"), "Slash suggestions should live beside the slash catalog.")
        XCTAssertTrue(catalogText.contains("struct SlashCommandDefinition"), "Slash command metadata should live beside the slash catalog.")
        XCTAssertTrue(catalogText.contains("enum SlashCommandCatalog"), "Slash command discovery and ranking should live in a focused catalog file.")
        XCTAssertTrue(catalogText.contains("static let definitions"), "Slash command definitions should not live beside parser control flow.")
        XCTAssertTrue(catalogText.contains("static func suggestions"), "Composer suggestion ranking should live beside the slash catalog.")
        XCTAssertTrue(slashText.contains("enum SlashCommandParser"), "SlashCommand.swift should own parser control flow.")
        XCTAssertTrue(pullRequestSlashText.contains("ToolArguments.json("), "Slash PR parser should still construct structured tool calls through core arguments.")
        XCTAssertFalse(slashText.contains("public struct SlashCommandSuggestionSurface"), "Slash parser should not own suggestion surface DTOs.")
        XCTAssertFalse(slashText.contains("struct SlashCommandDefinition"), "Slash parser should not own slash command metadata records.")
        XCTAssertFalse(slashText.contains("static let definitions"), "Slash parser should not own the slash command catalog.")
        XCTAssertFalse(slashText.contains("private static func score"), "Slash parser should not own catalog ranking.")
    }

    func testWorkspaceModelDelegatesRemoteProjectToolExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceRemoteProjectToolExecutor.swift")
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

        XCTAssertTrue(executorText.contains("struct WorkspaceRemoteProjectToolExecutor"), "SSH Remote project tools should live in a focused executor.")
        XCTAssertTrue(executorText.contains("static let toolDefinitions"), "Remote project tool definitions should live beside remote execution.")
        XCTAssertTrue(executorText.contains("static let gitToolNames"), "Remote git routing should live beside remote execution.")
        XCTAssertTrue(executorText.contains("static func executionOverride"), "Remote agent override construction should be directly testable.")
        XCTAssertTrue(executorText.contains("static func execute"), "Manual remote tool execution should be directly testable.")
        XCTAssertTrue(gitPlannerText.contains("struct WorkspaceRemoteGitToolRequest"), "Remote git command planning should return a typed request contract.")
        XCTAssertTrue(gitPlannerText.contains("enum WorkspaceRemoteGitToolRequestPlanner"), "Remote git command planning should live in a pure planner.")
        XCTAssertTrue(basicBuilderText.contains("enum WorkspaceRemoteGitBasicCommandBuilder"), "Remote basic git command construction should live in a focused builder.")
        XCTAssertTrue(basicBuilderText.contains("WorkspaceRemoteProjectPath.relativePath"), "Remote basic git commands should reuse remote path validation.")
        XCTAssertTrue(basicBuilderText.contains("GitToolError.emptyCommitMessage"), "Remote basic git commands should preserve commit-message validation.")
        XCTAssertTrue(hunkBuilderText.contains("enum WorkspaceRemoteGitHunkCommandBuilder"), "Remote git hunk command construction should live in a focused builder.")
        XCTAssertTrue(hunkBuilderText.contains("GitPatchToolExecutor.mismatchedPatchPath"), "Remote hunk command construction should reuse shared patch path validation.")
        XCTAssertTrue(pushBuilderText.contains("enum WorkspaceRemoteGitPushCommandBuilder"), "Remote git push command construction should live in a focused builder.")
        XCTAssertTrue(pushBuilderText.contains("GitInputValidator.safeName"), "Remote git push command construction should reuse shared git input validation.")
        XCTAssertTrue(pullRequestBuilderText.contains("enum WorkspaceRemoteGitHubPullRequestCommandBuilder"), "Remote GitHub PR command construction should live in a focused builder.")
        XCTAssertTrue(pullRequestBuilderText.contains("WorkspaceRemoteGitHubPullRequestBaseCommandBuilder.command"), "Remote GitHub PR dispatch should delegate creation and read-only commands.")
        XCTAssertTrue(pullRequestBuilderText.contains("WorkspaceRemoteGitHubPullRequestEditCommandBuilder.command"), "Remote GitHub PR dispatch should delegate edit commands.")
        XCTAssertTrue(pullRequestBuilderText.contains("WorkspaceRemoteGitHubPullRequestReviewCommandBuilder.command"), "Remote GitHub PR dispatch should delegate review-thread commands.")
        XCTAssertTrue(pullRequestBuilderText.contains("WorkspaceRemoteGitHubPullRequestMergeCommandBuilder.command"), "Remote GitHub PR dispatch should delegate merge commands.")
        XCTAssertFalse(pullRequestBuilderText.contains("gh api"), "Remote GitHub PR dispatch should not own GitHub API shell assembly.")
        XCTAssertFalse(pullRequestBuilderText.contains("GitInputValidator.trimmedNonEmpty"), "Remote GitHub PR dispatch should not own PR argument validation.")
        XCTAssertFalse(pullRequestBuilderText.contains("args."), "Remote GitHub PR dispatch should not decode individual PR arguments inline.")
        XCTAssertTrue(pullRequestBaseBuilderText.contains("ToolDefinition.gitPullRequestCreate.name"), "Remote PR base commands should own create/view/checks/diff/checkout dispatch.")
        XCTAssertTrue(pullRequestBaseBuilderText.contains("WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector"), "Remote PR base commands should reuse shared selector assembly.")
        XCTAssertTrue(pullRequestEditBuilderText.contains("GitHubPullRequestInputValidator.safeReviewers"), "Remote PR edit commands should reuse local reviewer validation.")
        XCTAssertTrue(pullRequestReviewBuilderText.contains("WorkspaceRemoteProjectPath.relativePath"), "Remote PR review comments should reuse remote path validation.")
        XCTAssertTrue(pullRequestReviewBuilderText.contains("GitHubPullRequestReviewThreadsQuery.graphql"), "Remote PR review thread listing should share the local GraphQL query.")
        XCTAssertTrue(pullRequestMergeBuilderText.contains("GitHubPullRequestInputValidator.safeMergeFlag"), "Remote PR merge commands should reuse local merge validation.")
        XCTAssertTrue(pullRequestSupportText.contains("GitHubPullRequestInputValidator.safeSelector"), "Remote PR command support should centralize selector validation.")
        XCTAssertTrue(pullRequestSupportText.contains("WorkspaceRemoteShellCommandFormatter.command"), "Remote PR command support should centralize shell command quoting.")
        XCTAssertTrue(remoteShellFormatterText.contains("WorkspaceTerminalSessionAdapter.shellSingleQuoted"), "Remote shell command quoting should live in one shared formatter.")
        XCTAssertTrue(worktreeBuilderText.contains("enum WorkspaceRemoteGitWorktreeCommandBuilder"), "Remote git worktree command construction should live in a focused builder.")
        XCTAssertTrue(worktreeBuilderText.contains("WorkspaceRemoteProjectPath.worktreePath"), "Remote worktree command construction should reuse remote path normalization.")
        XCTAssertTrue(remotePathText.contains("enum WorkspaceRemoteProjectPath"), "Remote path normalization should live in a focused helper.")
        XCTAssertTrue(executorText.contains("WorkspaceRemoteGitToolRequestPlanner.request"), "Remote executor should delegate git command planning.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitBasicCommandBuilder.command"), "Remote git planning should delegate basic command construction.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitHunkCommandBuilder.command"), "Remote git planning should delegate hunk command construction.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitPushCommandBuilder.command"), "Remote git planning should delegate push command construction.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitHubPullRequestCommandBuilder.command"), "Remote git planning should delegate PR command construction.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitWorktreeCommandBuilder.plan"), "Remote git planning should delegate worktree command construction.")
        XCTAssertTrue(executorText.contains("WorkspaceRemoteProjectPath.relativePath"), "Remote executor should delegate file path normalization.")
        XCTAssertTrue(builderText.contains("WorkspaceRemoteProjectToolExecutor.toolDefinitions"), "Agent run context builder should delegate remote base tool definitions.")
        XCTAssertTrue(builderText.contains("WorkspaceRemoteProjectToolExecutor.executionOverride"), "Agent run context builder should delegate remote override creation.")
        XCTAssertTrue(toolRunsText.contains("WorkspaceToolRunCoordinator"), "Generic tool runs should delegate orchestration to the focused coordinator.")
        XCTAssertTrue(try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift").contains("WorkspaceToolCallExecutorFactory.executor"), "The tool-run coordinator should delegate shared executor construction.")
        XCTAssertTrue(try Self.appSourceText(named: "WorkspaceToolCallExecutorFactory.swift").contains("WorkspaceToolCallExecutor("), "Shared workspace executor construction should live in the focused factory.")
        XCTAssertFalse(modelText.contains("func workspaceToolCallExecutor"), "WorkspaceModel.swift should not own the shared workspace executor factory.")
        XCTAssertTrue(try Self.appSourceText(named: "WorkspaceToolCallExecutor.swift").contains("WorkspaceRemoteProjectToolExecutor.execute"), "WorkspaceToolCallExecutor should own remote project routing.")
        XCTAssertFalse(modelText.contains("WorkspaceRemoteProjectToolExecutor.toolDefinitions"), "WorkspaceModel should not choose remote base tool definitions inline.")
        XCTAssertFalse(modelText.contains("WorkspaceRemoteProjectToolExecutor.executionOverride"), "WorkspaceModel should not create remote agent overrides inline.")
        XCTAssertFalse(executorText.contains("private static func remoteGitPullRequestCommand"), "Remote executor should not own GitHub CLI command construction.")
        XCTAssertFalse(gitPlannerText.contains("git status --short --branch"), "Generic remote git planning should not own basic git command strings.")
        XCTAssertFalse(gitPlannerText.contains("git add --"), "Generic remote git planning should not own git stage command construction.")
        XCTAssertFalse(gitPlannerText.contains("git commit -m"), "Generic remote git planning should not own git commit command construction.")
        XCTAssertFalse(gitPlannerText.contains("private static func remoteGitPullRequest"), "Generic remote git planning should not own GitHub CLI command construction.")
        XCTAssertFalse(gitPlannerText.contains(#"["gh", "pr""#), "Generic remote git planning should not assemble gh pr arguments inline.")
        XCTAssertFalse(executorText.contains("private static func remoteGitWorktreePath"), "Remote executor should not own worktree path normalization.")
        XCTAssertFalse(gitPlannerText.contains("private static func remoteGitHunk"), "Generic remote git planning should not own hunk patch transport construction.")
        XCTAssertFalse(gitPlannerText.contains("quillcode-hunk"), "Generic remote git planning should not own hunk patch temp-file details.")
        XCTAssertFalse(gitPlannerText.contains("private static func remoteGitPush"), "Generic remote git planning should not own push command construction.")
        XCTAssertFalse(gitPlannerText.contains("branch=$(git branch --show-current)"), "Generic remote git planning should not own current-branch push guards.")
        XCTAssertFalse(gitPlannerText.contains("private static func remoteGitWorktree"), "Generic remote git planning should not own worktree command construction.")
        XCTAssertFalse(gitPlannerText.contains(#"["git", "worktree""#), "Generic remote git planning should not assemble git worktree arguments inline.")
        XCTAssertFalse(modelText.contains("executeRemoteGitToolCall"), "WorkspaceModel should not own remote git command execution.")
        XCTAssertFalse(modelText.contains("executeRemoteShellToolCall"), "WorkspaceModel should not own remote shell command execution.")
        XCTAssertFalse(modelText.contains("remoteProjectGitToolNames"), "WorkspaceModel should not own remote git tool routing.")
        XCTAssertFalse(modelText.contains("remoteProjectRelativePath"), "WorkspaceModel should not own remote path normalization.")
    }

    func testGitToolDefinitionsLiveOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let definitionsText = try Self.toolsSourceText(named: "GitToolDefinitions.swift")

        XCTAssertTrue(definitionsText.contains("public extension ToolDefinition"), "Git tool schema should live in the definitions catalog.")
        XCTAssertTrue(definitionsText.contains("static let gitStatus"), "Git command definitions should remain available from the catalog.")
        XCTAssertTrue(definitionsText.contains("static let gitPullRequestMerge"), "GitHub PR definitions should remain available from the catalog.")
        XCTAssertTrue(definitionsText.contains("static let gitWorktreeRemove"), "Worktree definitions should remain available from the catalog.")
        XCTAssertTrue(definitionsText.contains("static let gitWorktreePrune"), "Worktree cleanup definitions should remain available from the catalog.")
        XCTAssertFalse(executorText.contains("public extension ToolDefinition"), "GitToolExecutor should not own tool schema declarations.")
        XCTAssertFalse(executorText.contains("parametersJSON"), "GitToolExecutor should not own JSON schema strings.")
    }

    func testGitHubPullRequestMetadataResolutionStaysFocused() throws {
        let executorText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutor.swift")
        let resolverText = try Self.toolsSourceText(named: "GitHubPullRequestMetadataResolver.swift")
        let resolverTests = try Self.toolsTestSourceText(named: "GitHubPullRequestMetadataResolverTests.swift")

        XCTAssertTrue(resolverText.contains("struct GitHubPullRequestMetadataResolver"), "GitHub PR metadata lookup should live in a focused resolver.")
        XCTAssertTrue(resolverText.contains("struct GitHubPullRequestMetadata"), "GitHub PR metadata records should live beside the resolver.")
        XCTAssertTrue(resolverText.contains("struct GitHubRepositoryMetadata"), "GitHub repository metadata records should live beside the resolver.")
        XCTAssertTrue(resolverText.contains("func pullRequest(selector: String?, cwd: URL)"), "PR metadata resolution should be directly testable.")
        XCTAssertTrue(resolverText.contains("func repository(cwd: URL)"), "Repository metadata resolution should be directly testable.")
        XCTAssertTrue(resolverText.contains("JSONDecoder().decode"), "Metadata JSON decoding should live in the resolver.")
        XCTAssertTrue(executorText.contains("metadataResolver.pullRequest"), "GitHub PR executor should delegate PR metadata resolution.")
        XCTAssertTrue(executorText.contains("metadataResolver.repository"), "GitHub PR executor should delegate repository metadata resolution.")
        XCTAssertTrue(resolverTests.contains("testResolverUsesGitHubCLIAndDecodesMetadata"), "Metadata resolver needs focused success coverage.")
        XCTAssertTrue(resolverTests.contains("testResolverRejectsInvalidPullRequestMetadata"), "Metadata resolver needs focused invalid PR metadata coverage.")
        XCTAssertTrue(resolverTests.contains("testResolverRejectsInvalidRepositoryMetadata"), "Metadata resolver needs focused invalid repository metadata coverage.")
        XCTAssertFalse(executorText.contains("struct PullRequestMetadata"), "GitHub PR executor should not own PR metadata records.")
        XCTAssertFalse(executorText.contains("struct RepositoryMetadata"), "GitHub PR executor should not own repository metadata records.")
        XCTAssertFalse(executorText.contains("func resolvePullRequest"), "GitHub PR executor should not own PR metadata resolution.")
        XCTAssertFalse(executorText.contains("func resolveRepository"), "GitHub PR executor should not own repository metadata resolution.")
        XCTAssertFalse(executorText.contains("JSONDecoder().decode"), "GitHub PR executor should not own metadata JSON decoding.")
    }

    func testToolRouterDelegatesGitToolCallDispatch() throws {
        let routerText = try Self.toolsSourceText(named: "ToolRouter.swift")
        let dispatcherText = try Self.toolsSourceText(named: "GitToolCallDispatcher.swift")

        XCTAssertTrue(dispatcherText.contains("struct GitToolCallDispatcher"), "Git tool call routing should live in a focused dispatcher.")
        XCTAssertTrue(dispatcherText.contains("static let definitions"), "The git dispatcher should own the git tool definition list.")
        XCTAssertTrue(dispatcherText.contains("func execute("), "The git dispatcher should expose a directly testable execution boundary.")
        XCTAssertTrue(routerText.contains("GitToolCallDispatcher.definitions"), "ToolRouter should compose git definitions from the dispatcher.")
        XCTAssertTrue(routerText.contains("GitToolCallDispatcher.handles"), "ToolRouter should delegate git tool dispatch.")
        XCTAssertFalse(routerText.contains("ToolDefinition.gitStatus.name"), "ToolRouter should not own local git route branches.")
        XCTAssertFalse(routerText.contains("ToolDefinition.gitPullRequestCreate.name"), "ToolRouter should not own GitHub PR route branches.")
        XCTAssertFalse(routerText.contains("ToolDefinition.gitWorktreeCreate.name"), "ToolRouter should not own worktree route branches.")
        XCTAssertFalse(routerText.contains("git.createPullRequest"), "ToolRouter should not call GitHub PR execution directly.")
        XCTAssertFalse(routerText.contains("git.createWorktree"), "ToolRouter should not call worktree execution directly.")
    }

    func testToolRouterDelegatesShellToolCallDispatch() throws {
        let routerText = try Self.toolsSourceText(named: "ToolRouter.swift")
        let dispatcherText = try Self.toolsSourceText(named: "ShellToolCallDispatcher.swift")

        XCTAssertTrue(dispatcherText.contains("struct ShellToolCallDispatcher"), "Shell tool call routing should live in a focused dispatcher.")
        XCTAssertTrue(dispatcherText.contains("static let definitions"), "The shell dispatcher should own the shell tool definition list.")
        XCTAssertTrue(dispatcherText.contains("EnvironmentOverridePolicy.validateOverrides"), "The shell dispatcher should own shell environment override validation.")
        XCTAssertTrue(dispatcherText.contains("func execute("), "The shell dispatcher should expose a directly testable execution boundary.")
        XCTAssertTrue(routerText.contains("ShellToolCallDispatcher.definitions"), "ToolRouter should compose shell definitions from the dispatcher.")
        XCTAssertTrue(routerText.contains("ShellToolCallDispatcher.handles"), "ToolRouter should delegate shell tool dispatch.")
        XCTAssertFalse(routerText.contains("ToolDefinition.shellRun.name"), "ToolRouter should not own shell route branches.")
        XCTAssertFalse(routerText.contains("EnvironmentOverridePolicy.validateOverrides"), "ToolRouter should not own shell environment override validation.")
        XCTAssertFalse(routerText.contains("Shell cwd must stay inside the current workspace."), "ToolRouter should not own shell cwd validation copy.")
        XCTAssertFalse(routerText.contains("Shell timeoutSeconds must be between"), "ToolRouter should not own shell timeout validation copy.")
    }

    func testShellExecutorDelegatesStreamingProcessLifecycle() throws {
        let executorText = try Self.toolsSourceText(named: "ShellToolExecutor.swift")
        let runnerText = try Self.toolsSourceText(named: "ShellStreamingProcessRunner.swift")
        let shellTestsText = try Self.toolsTestSourceText(named: "ShellToolExecutorTests.swift")

        XCTAssertTrue(runnerText.contains("final class ShellStreamingProcessRunner"), "Streaming shell lifecycle should have a focused owner.")
        XCTAssertTrue(runnerText.contains("AsyncStream<ShellProcessEvent>.Continuation"), "The streaming runner should own event continuation handling.")
        XCTAssertTrue(runnerText.contains("process.waitUntilExit()"), "The streaming runner should own process waiting.")
        XCTAssertTrue(runnerText.contains("private func timeout()"), "The streaming runner should own timeout termination.")
        XCTAssertTrue(executorText.contains("ShellStreamingProcessRunner(request:"), "ShellToolExecutor should delegate streaming execution.")
        XCTAssertFalse(executorText.contains("private final class StreamingShellProcess"), "ShellToolExecutor should not own streaming process internals.")
        XCTAssertFalse(executorText.contains("process.waitUntilExit()"), "Blocking ShellToolExecutor should not own streaming wait lifecycle.")
        XCTAssertTrue(shellTestsText.contains("testStreamingShellTimeoutKeepsPartialOutputAndStopsProcess"), "Streaming timeout behavior should have focused coverage.")
    }

    func testShellToolExecutorCoverageLivesOutsideMixedToolSuite() throws {
        let shellTestsText = try Self.toolsTestSourceText(named: "ShellToolExecutorTests.swift")
        let supportText = try Self.toolsTestSourceText(named: "ToolTestSupport.swift")

        XCTAssertTrue(shellTestsText.contains("final class ShellToolExecutorTests"), "Shell and SSH shell executor coverage should live in a focused suite.")
        XCTAssertTrue(shellTestsText.contains("testShellRunsWhoami"), "Blocking shell coverage should stay beside shell executor tests.")
        XCTAssertTrue(shellTestsText.contains("testStreamingShellTimeoutKeepsPartialOutputAndStopsProcess"), "Streaming shell coverage should stay beside shell executor tests.")
        XCTAssertTrue(shellTestsText.contains("testSSHRemoteShellBuildsNonInteractiveRequest"), "SSH shell request coverage should stay beside shell executor tests.")
        XCTAssertTrue(supportText.contains("extension XCTestCase"), "Tool test fixtures should live in shared support instead of one mixed suite.")
        XCTAssertTrue(supportText.contains("func makeFakeSSH"), "SSH test fixture creation should be reusable across focused tool suites.")
    }

    func testPrimitiveAndShellRouterToolCoverageLivesOutsideMixedToolSuite() throws {
        let fileTestsText = try Self.toolsTestSourceText(named: "FileToolExecutorTests.swift")
        let patchTestsText = try Self.toolsTestSourceText(named: "PatchToolExecutorTests.swift")
        let shellRouterTestsText = try Self.toolsTestSourceText(named: "ShellToolRouterTests.swift")
        let mixedSuitePath = Self.packageRoot()
            .appendingPathComponent("Tests/QuillCodeToolsTests/ToolTests.swift")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: mixedSuitePath.path),
            "The mixed ToolTests.swift catch-all should stay retired."
        )
        XCTAssertTrue(
            fileTestsText.contains("final class FileToolExecutorTests"),
            "File primitive coverage should live in a focused suite."
        )
        XCTAssertTrue(
            patchTestsText.contains("final class PatchToolExecutorTests"),
            "Generic apply-patch primitive coverage should live in a focused suite."
        )
        XCTAssertTrue(
            shellRouterTestsText.contains("final class ShellToolRouterTests"),
            "Shell tool router boundary coverage should live in a focused suite."
        )
        XCTAssertTrue(
            fileTestsText.contains("testFileWriteStaysInsideWorkspace"),
            "File path containment coverage should stay beside file tool tests."
        )
        XCTAssertTrue(
            patchTestsText.contains("testApplyPatchRejectsUnsafePaths"),
            "Patch path containment coverage should stay beside patch tool tests."
        )
        XCTAssertTrue(
            shellRouterTestsText.contains("testToolRouterShellRejectsSymlinkCWDEscape"),
            "Shell router cwd containment coverage should stay beside shell router tests."
        )
    }

    func testGitHubPullRequestToolCoverageLivesOutsideMixedToolSuite() throws {
        let pullRequestTestsText = try Self.toolsTestSourceText(named: "GitHubPullRequestToolExecutorTests.swift")

        XCTAssertTrue(
            pullRequestTestsText.contains("final class GitHubPullRequestToolExecutorTests"),
            "GitHub PR command construction and routing coverage should live in a focused suite."
        )
        XCTAssertTrue(
            pullRequestTestsText.contains("struct GitHubCLIFixture"),
            "GitHub PR tests should share the fake gh fixture instead of repeating setup in each test."
        )
        XCTAssertTrue(
            pullRequestTestsText.contains("testCreatePullRequestUsesGitHubCLIArguments"),
            "PR creation coverage should stay beside the GitHub PR executor tests."
        )
        XCTAssertTrue(
            pullRequestTestsText.contains("testToolRouterRoutesPullRequestReadAndMutationTools"),
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

        XCTAssertTrue(localText.contains("public struct GitLocalToolExecutor"), "Local git execution should live in a focused executor.")
        XCTAssertTrue(localText.contains("func status("), "Local git status should be directly testable.")
        XCTAssertTrue(localText.contains("func diff("), "Local git diff should be directly testable.")
        XCTAssertTrue(localText.contains("func stage("), "Local git stage should be directly testable.")
        XCTAssertTrue(localText.contains("func restore("), "Local git restore should be directly testable.")
        XCTAssertTrue(localText.contains("func commit("), "Local git commit should be directly testable.")
        XCTAssertTrue(localText.contains("func push("), "Local git push should be directly testable.")
        XCTAssertTrue(localText.contains("GitInputValidator.safeRelativePath"), "Local git file actions should use the shared path validator.")
        XCTAssertTrue(executorText.contains("private let local: GitLocalToolExecutor"), "GitToolExecutor should delegate local git work.")
        XCTAssertFalse(executorText.contains(#"["add", "--""#), "GitToolExecutor should not build git add arguments inline.")
        XCTAssertFalse(executorText.contains(#"["restore"]"#), "GitToolExecutor should not build git restore arguments inline.")
        XCTAssertFalse(executorText.contains(#"["commit", "-m""#), "GitToolExecutor should not build git commit arguments inline.")
        XCTAssertFalse(executorText.contains(#"["push"]"#), "GitToolExecutor should not build git push arguments inline.")
        XCTAssertFalse(executorText.contains("currentBranchName"), "GitToolExecutor should not own current-branch lookup.")
    }

    func testGitHubPullRequestExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let pullRequestText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutor.swift")
        let inputValidatorText = try Self.toolsSourceText(named: "GitHubPullRequestInputValidator.swift")
        let outputParserText = try Self.toolsSourceText(named: "GitHubPullRequestOutputParser.swift")
        let processRunnerText = try Self.toolsSourceText(named: "GitProcessRunner.swift")

        XCTAssertTrue(pullRequestText.contains("public struct GitHubPullRequestToolExecutor"), "GitHub PR execution should live in a focused executor.")
        XCTAssertTrue(pullRequestText.contains("func createPullRequest"), "GitHub PR creation should be directly testable.")
        XCTAssertTrue(pullRequestText.contains("func merge("), "GitHub PR merge command construction should be directly testable.")
        XCTAssertTrue(inputValidatorText.contains("public enum GitHubPullRequestInputValidator"), "GitHub PR input validation should live in a focused helper.")
        XCTAssertTrue(inputValidatorText.contains("static func safeSelector"), "GitHub PR selector validation should be directly testable.")
        XCTAssertTrue(inputValidatorText.contains("static func safeReviewers"), "GitHub PR reviewer validation should be directly testable.")
        XCTAssertTrue(outputParserText.contains("public enum GitHubPullRequestOutputParser"), "GitHub PR output parsing should live in a focused helper.")
        XCTAssertTrue(outputParserText.contains("static func extractURLs"), "GitHub PR URL extraction should be directly testable.")
        XCTAssertTrue(pullRequestText.contains("GitHubPullRequestInputValidator.safeSelector"), "GitHub PR execution should delegate selector validation.")
        XCTAssertTrue(pullRequestText.contains("GitHubPullRequestOutputParser.extractURLs"), "GitHub PR execution should delegate URL artifact parsing.")
        XCTAssertTrue(processRunnerText.contains("public struct GitProcessRunner"), "Git and GitHub CLI process launching should live in a reusable runner.")
        XCTAssertTrue(processRunnerText.contains("func runGitHub"), "GitHub CLI invocation should be owned by the process runner.")
        XCTAssertTrue(executorText.contains("private let pullRequests: GitHubPullRequestToolExecutor"), "GitToolExecutor should delegate GitHub PR work.")
        XCTAssertFalse(executorText.contains("func runGitHub"), "GitToolExecutor should not own GitHub CLI process launching.")
        XCTAssertFalse(executorText.contains("Process()"), "GitToolExecutor should not own raw process launching.")
        XCTAssertFalse(executorText.contains(#"["pr", "create"]"#), "GitToolExecutor should not build GitHub PR command arguments inline.")
        XCTAssertFalse(executorText.contains("addURLArtifacts"), "GitToolExecutor should not own GitHub PR URL artifact extraction.")
        XCTAssertFalse(pullRequestText.contains("static func safeSelector"), "GitHub PR execution should not own input validation.")
        XCTAssertFalse(pullRequestText.contains("static func extractURLs"), "GitHub PR execution should not own output parsing.")
    }

    func testGitWorktreeExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let worktreeText = try Self.toolsSourceText(named: "GitWorktreeToolExecutor.swift")

        XCTAssertTrue(worktreeText.contains("public struct GitWorktreeToolExecutor"), "Git worktree execution should live in a focused executor.")
        XCTAssertTrue(worktreeText.contains("func list("), "Git worktree listing should be directly testable.")
        XCTAssertTrue(worktreeText.contains("func create("), "Git worktree creation should be directly testable.")
        XCTAssertTrue(worktreeText.contains("func open("), "Git worktree opening should be directly testable.")
        XCTAssertTrue(worktreeText.contains("func remove("), "Git worktree removal should be directly testable.")
        XCTAssertTrue(worktreeText.contains("func prune("), "Git worktree cleanup should be directly testable.")
        XCTAssertTrue(worktreeText.contains("static func safePath"), "Git worktree path validation should live beside worktree execution.")
        XCTAssertTrue(worktreeText.contains("registeredPaths"), "Git worktree registered-path lookup should live beside worktree open/remove.")
        XCTAssertTrue(executorText.contains("private let worktrees: GitWorktreeToolExecutor"), "GitToolExecutor should delegate git worktree work.")
        XCTAssertFalse(executorText.contains(#"["worktree", "add"]"#), "GitToolExecutor should not build git worktree add arguments inline.")
        XCTAssertFalse(executorText.contains(#"["worktree", "remove"]"#), "GitToolExecutor should not build git worktree remove arguments inline.")
        XCTAssertFalse(executorText.contains("safeWorktreePath"), "GitToolExecutor should not own worktree path validation.")
        XCTAssertFalse(executorText.contains("registeredWorktreePaths"), "GitToolExecutor should not own registered-worktree lookup.")
    }

    func testGitPatchExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let patchText = try Self.toolsSourceText(named: "GitPatchToolExecutor.swift")
        let remoteGitHunkBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHunkCommandBuilder.swift")
        let remoteGitPlannerText = try Self.appSourceText(named: "WorkspaceRemoteGitToolRequestPlanner.swift")

        XCTAssertTrue(patchText.contains("public struct GitPatchToolExecutor"), "Git patch execution should live in a focused executor.")
        XCTAssertTrue(patchText.contains("func stageHunk("), "Git patch staging should be directly testable.")
        XCTAssertTrue(patchText.contains("func restoreHunk("), "Git patch restore should be directly testable.")
        XCTAssertTrue(patchText.contains("static func mismatchedPatchPath"), "Patch path validation should live beside patch execution.")
        XCTAssertTrue(executorText.contains("private let patches: GitPatchToolExecutor"), "GitToolExecutor should delegate hunk patch work.")
        XCTAssertTrue(remoteGitHunkBuilderText.contains("GitPatchToolExecutor.mismatchedPatchPath"), "Remote hunk planning should reuse the focused patch validator.")
        XCTAssertFalse(executorText.contains("private func applyHunk"), "GitToolExecutor should not own patch application.")
        XCTAssertFalse(executorText.contains("mismatchedPatchPath"), "GitToolExecutor should not own patch path validation.")
        XCTAssertFalse(executorText.contains("temporaryPatchFailed"), "GitToolExecutor should not own temporary patch file handling.")
        XCTAssertFalse(executorText.contains("pathsInDiffMetadataLine"), "GitToolExecutor should not own diff metadata parsing.")
        XCTAssertFalse(remoteGitPlannerText.contains("GitPatchToolExecutor.mismatchedPatchPath"), "Generic remote git planning should not own remote hunk patch validation.")
    }

    func testGitSharedInputValidationLivesOutsideGitFacade() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let localText = try Self.toolsSourceText(named: "GitLocalToolExecutor.swift")
        let validatorText = try Self.toolsSourceText(named: "GitInputValidator.swift")
        let pullRequestText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutor.swift")
        let worktreeText = try Self.toolsSourceText(named: "GitWorktreeToolExecutor.swift")
        let remoteGitPlannerText = try Self.appSourceText(named: "WorkspaceRemoteGitToolRequestPlanner.swift")
        let remoteGitPushBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitPushCommandBuilder.swift")

        XCTAssertTrue(validatorText.contains("public enum GitInputValidator"), "Shared git input validation should live in a neutral helper.")
        XCTAssertTrue(validatorText.contains("static let safeNameCharacters"), "Shared git-name character policy should live in GitInputValidator.")
        XCTAssertTrue(validatorText.contains("static func trimmedNonEmpty"), "Shared trimming should live in GitInputValidator.")
        XCTAssertTrue(validatorText.contains("static func safeName"), "Shared git name validation should live in GitInputValidator.")
        XCTAssertTrue(validatorText.contains("static func safeRelativePath"), "Shared local git path validation should live in GitInputValidator.")
        XCTAssertTrue(localText.contains("GitInputValidator.safeRelativePath"), "Local git execution should use the shared path validator.")
        XCTAssertTrue(pullRequestText.contains("GitInputValidator.safeName"), "GitHub PR execution should use the shared git-name validator.")
        XCTAssertTrue(worktreeText.contains("GitInputValidator.safeName"), "Worktree execution should use the shared git-name validator.")
        XCTAssertTrue(remoteGitPushBuilderText.contains("GitInputValidator.safeName"), "Remote git push planning should use the shared git-name validator.")
        XCTAssertTrue(remoteGitPushBuilderText.contains("GitInputValidator.safeNameCharacters"), "Remote git current-branch shell guards should use the shared git-name character policy.")
        XCTAssertFalse(executorText.contains("GitInputValidator.safeRelativePath"), "GitToolExecutor should not own local path validation.")
        XCTAssertFalse(pullRequestText.contains("GitToolExecutor.safeGitName"), "GitHub PR execution should not depend on the git facade for validation.")
        XCTAssertFalse(pullRequestText.contains("GitToolExecutor.trimmedNonEmpty"), "GitHub PR execution should not depend on the git facade for trimming.")
        XCTAssertFalse(worktreeText.contains("GitToolExecutor.safeGitName"), "Worktree execution should not depend on the git facade for validation.")
        XCTAssertFalse(worktreeText.contains("GitToolExecutor.trimmedNonEmpty"), "Worktree execution should not depend on the git facade for trimming.")
        XCTAssertFalse(remoteGitPlannerText.contains("GitToolExecutor.safeGitName"), "Remote git planning should not depend on the git facade for validation.")
        XCTAssertFalse(remoteGitPlannerText.contains("GitToolExecutor.trimmedNonEmpty"), "Remote git planning should not depend on the git facade for trimming.")
        XCTAssertFalse(remoteGitPlannerText.contains("GitInputValidator.safeName"), "Generic remote git planning should not own git-name validation.")
    }

    func testWorkspaceSurfaceDelegatesContextBannerBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceContextBannerBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceContextBannerBuilder"), "Context banner construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func banner() -> ContextBannerSurface?"), "Context banner construction should be directly testable.")
        XCTAssertTrue(builderText.contains("estimatedContextTokens"), "Context estimation should be directly testable.")
        XCTAssertTrue(surfaceText.contains("WorkspaceContextBannerBuilder("), "WorkspaceSurface should delegate context banner construction.")
        XCTAssertFalse(surfaceText.contains("private func contextBanner("), "WorkspaceSurface should not own context banner construction.")
        XCTAssertFalse(surfaceText.contains("contextUsedPercent"), "WorkspaceSurface should not own context usage calculation.")
        XCTAssertFalse(surfaceText.contains("estimatedContextTokens"), "WorkspaceSurface should not own context token estimation.")
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
