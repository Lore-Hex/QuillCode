import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class ToolTests: XCTestCase {
    func testShellRunsWhoami() {
        let result = ShellToolExecutor().run(.init(
            command: "whoami",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory())
        ))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertFalse(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testShellRejectsEmptyCommand() {
        let result = ShellToolExecutor().run(.init(
            command: " ",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory())
        ))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("No shell command") == true)
    }

    func testShellUsesExplicitEnvironment() {
        var environment = ProcessInfo.processInfo.environment
        environment["QUILL_CODE_TEST_ENV"] = "from-shell-request"
        let result = ShellToolExecutor().run(.init(
            command: "printf '%s' \"$QUILL_CODE_TEST_ENV\"",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            environment: environment
        ))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "from-shell-request")
    }

    func testCancellableShellStopsLongRunningCommand() async throws {
        let task = Task {
            await ShellToolExecutor().runCancellable(.init(
                command: "sleep 10; echo should-not-print",
                cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
                timeoutSeconds: 20
            ))
        }

        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let result = await task.value

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("cancelled") == true, result.error ?? "")
        XCTAssertFalse(result.stdout.contains("should-not-print"))
    }

    func testStreamingShellYieldsOutputBeforeCompletion() async throws {
        let stream = ShellToolExecutor().runStreaming(.init(
            command: "echo stream-start; sleep 0.2; echo stream-end",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 5
        ))
        var sawStartBeforeFinish = false
        var finishedResult: ToolResult?

        for await event in stream {
            switch event {
            case .stdout(let text):
                if finishedResult == nil, text.contains("stream-start") {
                    sawStartBeforeFinish = true
                }
            case .stderr:
                continue
            case .finished(let result):
                finishedResult = result
            }
        }

        let result = try XCTUnwrap(finishedResult)
        XCTAssertTrue(sawStartBeforeFinish)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("stream-start"))
        XCTAssertTrue(result.stdout.contains("stream-end"))
    }

    func testFileWriteStaysInsideWorkspace() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        let result = files.write(path: "nested/hello.txt", content: "hello world\n")
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(files.read(path: "nested/hello.txt").stdout, "hello world\n")
        XCTAssertFalse(files.write(path: "../escape.txt", content: "no").ok)
    }

    func testApplyPatchChangesWorkspaceFile() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("hello.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -hello
        +hello world
        """
        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello world\n")
    }

    func testApplyPatchRejectsUnsafePaths() throws {
        let root = try makeTempDirectory()
        let patch = """
        diff --git a/../escape.txt b/../escape.txt
        --- a/../escape.txt
        +++ b/../escape.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("unsafe path") == true, result.error ?? "")
    }

    func testGitStageStagesWorkspaceFileWithSpaces() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello world.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)

        let result = GitToolExecutor().stage(cwd: root, path: "hello world.txt")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        let status = GitToolExecutor().status(cwd: root)
        XCTAssertTrue(status.stdout.contains("A  "), status.stdout)
        XCTAssertTrue(status.stdout.contains("hello world.txt"), status.stdout)
    }

    func testGitRestoreRestoresTrackedWorkspaceFile() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        try "before\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root)).ok)
        try "after\n".write(to: file, atomically: true, encoding: .utf8)

        let result = GitToolExecutor().restore(cwd: root, path: "hello.txt")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "before\n")
    }

    func testGitStageHunkStagesSelectedPatch() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        try "one\ntwo\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root)).ok)
        try "one\nTWO\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """

        let result = GitToolExecutor().stageHunk(cwd: root, path: "hello.txt", patch: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(GitToolExecutor().diff(cwd: root, staged: true).stdout.contains("+TWO"))
        XCTAssertEqual(GitToolExecutor().diff(cwd: root).stdout, "")
    }

    func testGitStageHunkSupportsWorkspaceFileWithSpaces() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello world.txt")
        try "one\ntwo\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello world.txt").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root)).ok)
        try "one\nTWO\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello world.txt b/hello world.txt
        --- a/hello world.txt
        +++ b/hello world.txt
        @@ -1,2 +1,2 @@
         one
        -two
        +TWO
        """

        let result = GitToolExecutor().stageHunk(cwd: root, path: "hello world.txt", patch: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(GitToolExecutor().diff(cwd: root, staged: true).stdout.contains("+TWO"))
    }

    func testGitRestoreHunkRestoresSelectedPatch() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        try "one\ntwo\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root)).ok)
        try "one\nTWO\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """

        let result = GitToolExecutor().restoreHunk(cwd: root, path: "hello.txt", patch: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "one\ntwo\nthree\n")
        XCTAssertEqual(GitToolExecutor().status(cwd: root).stdout, "## \(currentBranchName(in: root))\n")
    }

    func testGitStageAndRestoreRejectOutsideWorkspacePaths() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let git = GitToolExecutor()

        let stage = git.stage(cwd: root, path: "../escape.txt")
        let restore = git.restore(cwd: root, path: "../escape.txt")

        XCTAssertFalse(stage.ok)
        XCTAssertTrue(stage.error?.contains("outside the workspace") == true, stage.error ?? "")
        XCTAssertFalse(restore.ok)
        XCTAssertTrue(restore.error?.contains("outside the workspace") == true, restore.error ?? "")
    }

    func testGitCommitCommitsStagedChanges() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)

        let result = GitToolExecutor().commit(cwd: root, message: "Add hello file")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        let log = ShellToolExecutor().run(.init(command: "git log -1 --pretty=%s", cwd: root))
        XCTAssertEqual(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Add hello file")
        XCTAssertFalse(GitToolExecutor().status(cwd: root).stdout.contains("hello.txt"))
    }

    func testGitCommitRejectsEmptyMessage() throws {
        let result = GitToolExecutor().commit(cwd: try makeTempDirectory(), message: " ")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("message is required") == true, result.error ?? "")
    }

    func testGitPushPushesCurrentBranchToNamedRemote() throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        let remote = parent.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepo(at: root)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init --bare '\(remote.path)'", cwd: parent)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git remote add origin '\(remote.path)'", cwd: root)).ok)
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "Add hello").ok)
        let branch = currentBranchName(in: root)

        let result = GitToolExecutor().push(cwd: root, remote: "origin", branch: branch, setUpstream: true)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        let remoteHead = ShellToolExecutor().run(.init(
            command: "git --git-dir='\(remote.path)' rev-parse \(branch)",
            cwd: parent
        ))
        XCTAssertTrue(remoteHead.ok, "\(remoteHead.error ?? "") \(remoteHead.stderr)")
        XCTAssertFalse(remoteHead.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testGitPushRejectsUnsafeRemoteAndBranchNames() throws {
        let root = try makeTempGitRepoWithInitialCommit()

        XCTAssertFalse(GitToolExecutor().push(cwd: root, remote: "--all").ok)
        XCTAssertFalse(GitToolExecutor().push(cwd: root, remote: "origin", branch: "feature;rm").ok)
    }

    func testGitCreatePullRequestUsesGitHubCLIArguments() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeGitHubCLI = try makeFakeGitHubCLI(in: root, argumentsFile: argumentsFile)
        let git = GitToolExecutor(githubCLIExecutable: fakeGitHubCLI)

        let result = git.createPullRequest(
            cwd: root,
            title: "Add PR tool",
            body: "Adds structured pull request creation.",
            base: "main",
            head: "feature/pr-tool",
            draft: true
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, [
            "pr",
            "create",
            "--title",
            "Add PR tool",
            "--body",
            "Adds structured pull request creation.",
            "--base",
            "main",
            "--head",
            "feature/pr-tool",
            "--draft"
        ])
    }

    func testGitCreatePullRequestRequiresTitleUnlessFillIsEnabled() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeGitHubCLI = try makeFakeGitHubCLI(in: root, argumentsFile: argumentsFile)
        let git = GitToolExecutor(githubCLIExecutable: fakeGitHubCLI)

        XCTAssertFalse(git.createPullRequest(cwd: root, title: " ").ok)

        let result = git.createPullRequest(cwd: root, fill: true)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, ["pr", "create", "--fill"])
    }

    func testGitWorktreeCreateListAndRemoveSibling() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let worktreeName = "quillcode-worktree-\(UUID().uuidString)"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let branch = "quillcode-\(UUID().uuidString.prefix(8))"
        let git = GitToolExecutor()

        let create = git.createWorktree(cwd: root, path: worktreeName, branch: String(branch))

        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        XCTAssertEqual(create.artifacts, [worktree.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.appendingPathComponent(".git").path))

        let list = git.listWorktrees(cwd: root)
        XCTAssertTrue(list.ok, "\(list.error ?? "") \(list.stderr)")
        XCTAssertTrue(list.stdout.contains(worktree.path), list.stdout)
        XCTAssertTrue(list.stdout.contains(String(branch)), list.stdout)

        let remove = git.removeWorktree(cwd: root, path: worktreeName)

        XCTAssertTrue(remove.ok, "\(remove.error ?? "") \(remove.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
    }

    func testGitWorktreeCreateRejectsUnsafePath() throws {
        let root = try makeTempGitRepoWithInitialCommit()

        let result = GitToolExecutor().createWorktree(cwd: root, path: "../outside")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("outside the workspace") == true, result.error ?? "")
    }

    func testGitWorktreeRemoveRejectsUnregisteredPath() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let unrelatedName = "not-a-worktree-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent(unrelatedName),
            withIntermediateDirectories: true
        )

        let result = GitToolExecutor().removeWorktree(cwd: root, path: unrelatedName, force: true)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("not registered") == true, result.error ?? "")
    }

    func testGitHunkActionsRejectPatchPathMismatch() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let patch = """
        diff --git a/other.txt b/other.txt
        --- a/other.txt
        +++ b/other.txt
        @@ -1 +1 @@
        -old
        +new
        """

        let result = GitToolExecutor().stageHunk(cwd: root, path: "hello.txt", patch: patch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("different path") == true, result.error ?? "")
    }

    func testToolRouterExposesGitStageAndRestoreDefinitions() {
        let definitions = ToolRouter.definitions.map(\.name)

        XCTAssertTrue(definitions.contains("host.git.stage"))
        XCTAssertTrue(definitions.contains("host.git.restore"))
        XCTAssertTrue(definitions.contains("host.git.stage_hunk"))
        XCTAssertTrue(definitions.contains("host.git.restore_hunk"))
        XCTAssertTrue(definitions.contains("host.git.commit"))
        XCTAssertTrue(definitions.contains("host.git.push"))
        XCTAssertTrue(definitions.contains("host.git.pr.create"))
        XCTAssertTrue(definitions.contains("host.git.worktree.list"))
        XCTAssertTrue(definitions.contains("host.git.worktree.create"))
        XCTAssertTrue(definitions.contains("host.git.worktree.remove"))
    }

    func testToolRouterRoutesGitWorktreeList() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.gitWorktreeList.name,
            argumentsJSON: "{}"
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(root.path), result.stdout)
    }

    func testToolRouterRoutesGitPush() throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        let remote = parent.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepo(at: root)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init --bare '\(remote.path)'", cwd: parent)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git remote add origin '\(remote.path)'", cwd: root)).ok)
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "Add hello").ok)

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.gitPush.name,
            argumentsJSON: #"{"remote":"origin","setUpstream":true}"#
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }

    func testToolRouterRoutesGitPullRequestCreate() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeGitHubCLI = try makeFakeGitHubCLI(in: root, argumentsFile: argumentsFile)
        let router = ToolRouter(
            workspaceRoot: root,
            git: GitToolExecutor(githubCLIExecutable: fakeGitHubCLI)
        )

        let result = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestCreate.name,
            argumentsJSON: #"{"title":"Add PR route","base":"main","draft":true}"#
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, ["pr", "create", "--title", "Add PR route", "--base", "main", "--draft"])
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeToolTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempGitRepoWithInitialCommit() throws -> URL {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("README.md")
        try "# Test repo\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "README.md").ok)
        let commit = ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root))
        XCTAssertTrue(commit.ok, "\(commit.error ?? "") \(commit.stderr)")
        return root
    }

    private func initializeGitRepo(at root: URL) throws {
        let result = ShellToolExecutor().run(.init(
            command: "git init && git config user.email test@example.com && git config user.name QuillCodeTests",
            cwd: root
        ))
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }

    private func currentBranchName(in root: URL) -> String {
        let result = ShellToolExecutor().run(.init(command: "git branch --show-current", cwd: root))
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeFakeGitHubCLI(in root: URL, argumentsFile: URL) throws -> URL {
        let script = root.appendingPathComponent("fake-gh")
        let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsPath)'
        echo 'https://github.com/example/repo/pull/123'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
