import XCTest

final class ParityShellFileToolGateTests: QuillCodeParityTestCase {
    func testToolRouterDelegatesShellToolCallDispatch() throws {
        let routerText = try Self.toolsSourceText(named: "ToolRouter.swift")
        let dispatcherText = try Self.toolsSourceText(named: "ShellToolCallDispatcher.swift")

        Self.assertSource(dispatcherText, contains: "struct ShellToolCallDispatcher")
        Self.assertSource(dispatcherText, contains: "static let definitions")
        Self.assertSource(dispatcherText, contains: "EnvironmentOverridePolicy.validateOverrides")
        Self.assertSource(dispatcherText, contains: "func execute(")
        Self.assertSource(routerText, contains: "ShellToolCallDispatcher.definitions")
        Self.assertSource(routerText, contains: "ShellToolCallDispatcher.handles")
        Self.assertSource(routerText, excludes: "ToolDefinition.shellRun.name")
        Self.assertSource(routerText, excludes: "EnvironmentOverridePolicy.validateOverrides")
        Self.assertSource(routerText, excludes: "Shell cwd must stay inside the current workspace.")
        Self.assertSource(routerText, excludes: "Shell timeoutSeconds must be between")
    }

    func testShellExecutorDelegatesStreamingProcessLifecycle() throws {
        let executorText = try Self.toolsSourceText(named: "ShellToolExecutor.swift")
        let runnerText = try Self.toolsSourceText(named: "ShellStreamingProcessRunner.swift")
        let shellTestsText = try Self.toolsTestSourceText(named: "ShellToolExecutorTests.swift")

        Self.assertSource(runnerText, contains: "final class ShellStreamingProcessRunner")
        Self.assertSource(runnerText, contains: "AsyncStream<ShellProcessEvent>.Continuation")
        Self.assertSource(runnerText, contains: "process.waitUntilExit()")
        Self.assertSource(runnerText, contains: "private func timeout()")
        Self.assertSource(executorText, contains: "ShellStreamingProcessRunner(request:")
        Self.assertSource(executorText, excludes: "private final class StreamingShellProcess")
        Self.assertSource(executorText, excludes: "process.waitUntilExit()")
        Self.assertSource(shellTestsText, contains: "testStreamingShellTimeoutKeepsPartialOutputAndStopsProcess")
    }

    func testShellToolExecutorCoverageLivesOutsideMixedToolSuite() throws {
        let shellTestsText = try Self.toolsTestSourceText(named: "ShellToolExecutorTests.swift")
        let supportText = try Self.toolsTestSourceText(named: "ToolTestSupport.swift")

        Self.assertSource(shellTestsText, contains: "final class ShellToolExecutorTests")
        Self.assertSource(shellTestsText, contains: "testShellRunsWhoami")
        Self.assertSource(shellTestsText, contains: "testStreamingShellTimeoutKeepsPartialOutputAndStopsProcess")
        Self.assertSource(shellTestsText, contains: "testSSHRemoteShellBuildsNonInteractiveRequest")
        Self.assertSource(supportText, contains: "extension XCTestCase")
        Self.assertSource(supportText, contains: "func makeFakeSSH")
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

    func testFileToolExecutorDelegatesWorkspaceFileOperations() throws {
        let executorText = try Self.toolsSourceText(named: "FileToolExecutor.swift")
        let resolverText = try Self.toolsSourceText(named: "FileWorkspacePathResolver.swift")
        let listerText = try Self.toolsSourceText(named: "FileDirectoryLister.swift")
        let searchText = try Self.toolsSourceText(named: "FileSearchScanner.swift")
        let definitionsText = try Self.toolsSourceText(named: "FileToolDefinitions.swift")
        let limitsText = try Self.toolsSourceText(named: "FileToolLimits.swift")
        let indexerText = try Self.toolsSourceText(named: "WorkspaceFileIndexer.swift")

        XCTAssertTrue(
            executorText.contains("FileDirectoryLister(pathResolver:"),
            "FileToolExecutor should delegate directory listing."
        )
        XCTAssertTrue(
            executorText.contains("FileSearchScanner(pathResolver:"),
            "FileToolExecutor should delegate search scanning."
        )
        XCTAssertTrue(
            resolverText.contains("WorkspaceBoundary.isWithin"),
            "File path containment should live in the focused workspace resolver."
        )
        XCTAssertTrue(
            listerText.contains("contentsOfDirectory"),
            "Directory enumeration should live in FileDirectoryLister."
        )
        XCTAssertTrue(
            searchText.contains("enumerator("),
            "Recursive text scanning should live in FileSearchScanner."
        )
        XCTAssertTrue(
            definitionsText.contains("static let fileRead"),
            "File tool definitions should live outside the executor facade."
        )
        XCTAssertTrue(
            indexerText.contains("FileToolLimits.excludedWorkspaceDirectoryNames"),
            "Workspace file indexing should share the file-search directory exclusion policy."
        )
        XCTAssertTrue(
            limitsText.contains("excludedWorkspaceDirectoryNames"),
            "Shared file-tool limits should own directory exclusion policy."
        )
        XCTAssertFalse(
            executorText.contains("contentsOfDirectory"),
            "FileToolExecutor should not own directory enumeration."
        )
        XCTAssertFalse(
            executorText.contains("enumerator("),
            "FileToolExecutor should not own recursive search enumeration."
        )
        XCTAssertFalse(
            executorText.contains("public extension ToolDefinition"),
            "FileToolExecutor should not own tool definition metadata."
        )
    }

}
