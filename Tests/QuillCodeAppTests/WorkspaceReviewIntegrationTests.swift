import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceReviewIntegrationTests: XCTestCase {
    func testApplyPatchToolRunRefreshesReviewDiff() throws {
        let root = try makeCommittedLocalGitFile()
        let fileURL = root.appendingPathComponent("hello.txt")
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let model = QuillCodeWorkspaceModel()

        model.runToolCall(
            ToolCall(
                name: ToolDefinition.applyPatch.name,
                argumentsJSON: ToolArguments.json(["patch": patch])
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "new\n")
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            ToolDefinition.applyPatch.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertTrue(model.surface().review.isVisible)
        XCTAssertEqual(model.surface().review.files.map(\.path), ["hello.txt"])
        let lines = try XCTUnwrap(model.surface().review.files.first?.hunkItems.first?.lines)
        XCTAssertTrue(lines.contains(where: {
            $0.content == "new" && $0.kind == .insertion
        }))
    }

    func testRunReviewStageActionStagesFileAndRefreshesDiff() throws {
        let fixture = try makeLocalReviewFixture()

        fixture.model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .stage, path: "hello.txt"),
            workspaceRoot: fixture.root
        )

        XCTAssertEqual(fixture.model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(fixture.model.currentToolCards.map(\.title), [
            ToolDefinition.gitStage.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertTrue(fixture.model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertFalse(fixture.model.surface().review.isVisible)
        XCTAssertEqual(try runGit(["status", "--short"], cwd: fixture.root), "M  hello.txt\n")
    }

    func testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff() throws {
        let fixture = try makeRemoteReviewFixture(argumentsFileName: "ssh-review-stage-args.txt")

        fixture.model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .stage, path: "hello.txt"),
            workspaceRoot: fixture.localRoot
        )

        XCTAssertRemoteReviewToolCards(
            fixture.model.currentToolCards,
            expectedTitles: [ToolDefinition.gitStage.name, ToolDefinition.gitDiff.name]
        )
        XCTAssertEqual(try runGit(["status", "--short"], cwd: fixture.remoteRoot), "M  hello.txt\n")
        XCTAssertNoLocalReviewFileCopied(to: fixture.localRoot)
        XCTAssertTrue(try fixture.recordedSSHArguments().contains("git diff"))
    }

    func testAddReviewCommentAppendsThreadEventForVisibleDiffFile() throws {
        let diff = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1,2 @@
        +new
         old
        """
        let call = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let thread = ChatThread(
            title: "Review",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertTrue(model.addReviewComment(path: "hello.txt", text: "Keep this wording direct."))
        XCTAssertTrue(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            lineKind: .insertion,
            text: "Check the new line."
        ))
        XCTAssertTrue(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            endLineNumber: 2,
            lineKind: nil,
            text: "Keep these lines together."
        ))
        XCTAssertFalse(model.addReviewComment(path: "README.md", text: "Stale file"))
        XCTAssertFalse(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            endLineNumber: 4,
            lineKind: nil,
            text: "Invalid range"
        ))

        XCTAssertEqual(model.selectedThread?.events.filter { $0.kind == .reviewComment }.count, 3)
        XCTAssertEqual(model.surface().review.files.first?.comments.map(\.text), ["Keep this wording direct."])
        XCTAssertEqual(
            model.surface().review.files.first?.hunkItems.first?.lines.first?.comments.map(\.text),
            ["Check the new line.", "Keep these lines together."]
        )
        XCTAssertEqual(
            model.surface().review.files.first?.hunkItems.first?.lines.first?.comments.last?.lineRangeLabel,
            "Lines 1-2"
        )
    }

    func testRunReviewRestoreActionRestoresFileAndRefreshesDiff() throws {
        let fixture = try makeLocalReviewFixture()

        fixture.model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .restore, path: "hello.txt"),
            workspaceRoot: fixture.root
        )

        XCTAssertEqual(fixture.model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(fixture.model.currentToolCards.map(\.title), [
            ToolDefinition.gitRestore.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertTrue(fixture.model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertEqual(try String(contentsOf: fixture.fileURL, encoding: .utf8), "old\n")
        XCTAssertEqual(try runGit(["status", "--short"], cwd: fixture.root), "")
        XCTAssertFalse(fixture.model.surface().review.isVisible)
    }

    func testRemoteProjectReviewRestoreActionRunsThroughSSHAndRefreshesDiff() throws {
        let fixture = try makeRemoteReviewFixture(argumentsFileName: "ssh-review-restore-args.txt")

        fixture.model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .restore, path: "hello.txt"),
            workspaceRoot: fixture.localRoot
        )

        XCTAssertRemoteReviewToolCards(
            fixture.model.currentToolCards,
            expectedTitles: [ToolDefinition.gitRestore.name, ToolDefinition.gitDiff.name]
        )
        XCTAssertEqual(try String(contentsOf: fixture.remoteFileURL, encoding: .utf8), "old\n")
        XCTAssertEqual(try runGit(["status", "--short"], cwd: fixture.remoteRoot), "")
        XCTAssertNoLocalReviewFileCopied(to: fixture.localRoot)
        XCTAssertTrue(try fixture.recordedSSHArguments().contains("git diff"))
    }

    func testRunReviewStageHunkActionStagesPatchAndRefreshesDiff() throws {
        let fixture = try makeLocalReviewFixture(
            initial: "one\ntwo\nthree\n",
            changed: "one\nTWO\nthree\n"
        )

        fixture.model.runReviewAction(
            WorkspaceReviewActionSurface(
                kind: .stageHunk,
                path: "hello.txt",
                patch: twoLinePatch,
                targetID: "hello.txt:hunk-1"
            ),
            workspaceRoot: fixture.root
        )

        XCTAssertEqual(fixture.model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(fixture.model.currentToolCards.map(\.title), [
            ToolDefinition.gitStageHunk.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertTrue(fixture.model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertTrue(try runGit(["diff", "--staged"], cwd: fixture.root).contains("+TWO"))
        XCTAssertFalse(fixture.model.surface().review.isVisible)
    }

    func testRemoteProjectReviewStageHunkActionRunsThroughSSHAndRefreshesDiff() throws {
        let fixture = try makeRemoteReviewFixture(
            argumentsFileName: "ssh-review-stage-hunk-args.txt",
            initial: "one\ntwo\nthree\n",
            changed: "one\nTWO\nthree\n"
        )

        fixture.model.runReviewAction(
            WorkspaceReviewActionSurface(
                kind: .stageHunk,
                path: "hello.txt",
                patch: twoLinePatch,
                targetID: "hello.txt:hunk-1"
            ),
            workspaceRoot: fixture.localRoot
        )

        XCTAssertRemoteReviewToolCards(
            fixture.model.currentToolCards,
            expectedTitles: [ToolDefinition.gitStageHunk.name, ToolDefinition.gitDiff.name]
        )
        XCTAssertTrue(try runGit(["diff", "--staged"], cwd: fixture.remoteRoot).contains("+TWO"))
        XCTAssertNoLocalReviewFileCopied(to: fixture.localRoot)
        XCTAssertTrue(try fixture.recordedSSHArguments().contains("git diff"))
    }

    private var twoLinePatch: String {
        """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """
    }

    private func makeCommittedLocalGitFile(
        fileName: String = "hello.txt",
        initial: String = "old\n"
    ) throws -> URL {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        try initial.write(to: root.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        _ = try runGit(["add", fileName], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        return root
    }

    private func makeLocalReviewFixture(
        initial: String = "old\n",
        changed: String = "new\n"
    ) throws -> LocalReviewFixture {
        let root = try makeCommittedLocalGitFile(initial: initial)
        let fileURL = root.appendingPathComponent("hello.txt")
        try changed.write(to: fileURL, atomically: true, encoding: .utf8)
        let thread = ChatThread(title: "Review")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        return LocalReviewFixture(root: root, fileURL: fileURL, model: model)
    }

    private func makeRemoteReviewFixture(
        argumentsFileName: String,
        initial: String = "old\n",
        changed: String = "new\n"
    ) throws -> RemoteReviewFixture {
        let localRoot = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let remoteFileURL = remoteRoot.appendingPathComponent("hello.txt")
        try initial.write(to: remoteFileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: remoteRoot)
        _ = try runGit(["commit", "-m", "add hello"], cwd: remoteRoot)
        try changed.write(to: remoteFileURL, atomically: true, encoding: .utf8)

        let argumentsFile = localRoot.appendingPathComponent(argumentsFileName)
        let fakeSSH = try makeExecutingFakeSSH(in: localRoot, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let thread = ChatThread(title: "Remote Review", projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )
        return RemoteReviewFixture(
            localRoot: localRoot,
            remoteRoot: remoteRoot,
            remoteFileURL: remoteFileURL,
            argumentsFile: argumentsFile,
            model: model
        )
    }

    private func XCTAssertRemoteReviewToolCards(
        _ cards: [ToolCardState],
        expectedTitles: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(cards.map(\.title), expectedTitles, file: file, line: line)
        XCTAssertEqual(cards.map(\.executionContext?.kind), [.sshRemote, .sshRemote], file: file, line: line)
        XCTAssertTrue(cards.allSatisfy { $0.status == .done }, file: file, line: line)
    }

    private func XCTAssertNoLocalReviewFileCopied(
        to localRoot: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: localRoot.appendingPathComponent("hello.txt").path),
            file: file,
            line: line
        )
    }
}

private struct LocalReviewFixture {
    var root: URL
    var fileURL: URL
    var model: QuillCodeWorkspaceModel
}

private struct RemoteReviewFixture {
    var localRoot: URL
    var remoteRoot: URL
    var remoteFileURL: URL
    var argumentsFile: URL
    var model: QuillCodeWorkspaceModel

    func recordedSSHArguments() throws -> String {
        try String(contentsOf: argumentsFile, encoding: .utf8)
    }
}
