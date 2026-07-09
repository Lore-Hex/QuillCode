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

        // Workspace tool runs use the model's UI edit session, which refuses to patch an
        // existing file that session never read — record the fixture file as read there.
        model.uiEditSessionGuard.markRead(fileURL)
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

    func testRunReviewOpenActionReadsFileWithoutMutatingReview() throws {
        let fixture = try makeLocalReviewFixture()
        // Populate and show the review pane with the working-tree diff first.
        _ = fixture.model.runToolCall(
            ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"),
            workspaceRoot: fixture.root
        )
        XCTAssertTrue(fixture.model.surface().review.isVisible)
        let titlesBeforeOpen = fixture.model.currentToolCards.map(\.title)

        fixture.model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .open, path: "hello.txt"),
            workspaceRoot: fixture.root
        )

        // Open adds exactly one non-mutating host.file.read — no git diff refresh ...
        XCTAssertEqual(
            fixture.model.currentToolCards.map(\.title),
            titlesBeforeOpen + [ToolDefinition.fileRead.name]
        )
        XCTAssertTrue(fixture.model.currentToolCards.allSatisfy { $0.status == .done })
        // ... and the review pane is left intact (not cleared like stage/restore).
        XCTAssertTrue(fixture.model.surface().review.isVisible)
    }

    func testRunReviewOpenActionRefusesUnreadableReviewFile() throws {
        let diff = """
        diff --git a/Assets/logo.png b/Assets/logo.png
        Binary files a/Assets/logo.png and b/Assets/logo.png differ
        """
        let call = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let thread = ChatThread(
            title: "Review binary",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())

        XCTAssertEqual(model.surface().review.files.first?.unreadableReason, "Binary file")
        model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .open, path: "Assets/logo.png"),
            workspaceRoot: root
        )

        XCTAssertFalse(model.currentToolCards.contains { $0.title == ToolDefinition.fileRead.name })
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
        XCTAssertEqual(model.lastError, "Binary file cannot be opened from Review.")
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

    func testRemoteProjectReviewOpenActionReadsRemoteFileOverSSHWithoutClearing() throws {
        let fixture = try makeRemoteReviewFixture(argumentsFileName: "ssh-review-open-args.txt")

        // Show the review pane with the remote working-tree diff.
        _ = fixture.model.runToolCall(
            ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"),
            workspaceRoot: fixture.localRoot
        )
        XCTAssertTrue(fixture.model.surface().review.isVisible)

        fixture.model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .open, path: "hello.txt"),
            workspaceRoot: fixture.localRoot
        )

        // Open routed host.file.read over SSH, reading the REMOTE file (not a local copy) ...
        let lastCard = try XCTUnwrap(fixture.model.currentToolCards.last)
        XCTAssertEqual(lastCard.title, ToolDefinition.fileRead.name)
        XCTAssertEqual(lastCard.executionContext?.kind, .sshRemote)
        XCTAssertEqual(lastCard.status, .done)
        XCTAssertTrue(try fixture.recordedSSHArguments().contains("hello.txt"))
        XCTAssertNoLocalReviewFileCopied(to: fixture.localRoot)
        // ... and the review pane is left intact (no diff refresh, no clear).
        XCTAssertTrue(fixture.model.surface().review.isVisible)
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

    func testGitDiffReviewSurfaceSummarizesLatestCompletedDiff() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111111..2222222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,3 +1,4 @@
         import Foundation
        -let title = "Old"
        +let title = "QuillCode"
        +let subtitle = "Review"
        diff --git a/README.md b/README.md
        index 3333333..4444444 100644
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -Old README
        +New README
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let thread = ChatThread(
            title: "Review changes",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolRunning, summary: "host.git.diff running"),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let review = model.surface().review

        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.files.map(\.path), ["Sources/App.swift", "README.md"])
        XCTAssertEqual(review.totalInsertions, 3)
        XCTAssertEqual(review.totalDeletions, 2)
        XCTAssertEqual(review.totalHunks, 2)
        XCTAssertEqual(review.subtitle, "2 files changed, +3 -2")
        XCTAssertEqual(review.files.first?.actions.map(\.kind), [.open, .stage, .restore])
        XCTAssertEqual(review.files.first?.hunkItems.count, 1)
        XCTAssertEqual(review.files.first?.hunkItems.first?.actions.map(\.kind), [.stageHunk, .restoreHunk])
        XCTAssertTrue(review.files.first?.hunkItems.first?.patch.contains("diff --git a/Sources/App.swift b/Sources/App.swift") == true)
        let appLines = review.files.first?.hunkItems.first?.lines
        XCTAssertEqual(appLines?.map(\.kind), [.context, .deletion, .insertion, .insertion])
        XCTAssertEqual(appLines?.map(\.oldLineNumber), [1, 2, nil, nil])
        XCTAssertEqual(appLines?.map(\.newLineNumber), [1, nil, 2, 3])
    }

    func testGitDiffReviewSurfaceIncludesMatchingReviewComments() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1 +1,2 @@
        +let title = "QuillCode"
         import Foundation
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let matchingComment = WorkspaceReviewCommentState(path: "Sources/App.swift", text: "Check the public API name.")
        let lineComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            lineKind: .insertion,
            text: "This line should stay public."
        )
        let rangeComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            endLineNumber: 2,
            text: "Keep the title next to the import."
        )
        let staleComment = WorkspaceReviewCommentState(path: "README.md", text: "This file is no longer in the diff.")
        let thread = ChatThread(
            title: "Review changes",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift", payloadJSON: try JSONHelpers.encodePretty(matchingComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift:1", payloadJSON: try JSONHelpers.encodePretty(lineComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift:1-2", payloadJSON: try JSONHelpers.encodePretty(rangeComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on README.md", payloadJSON: try JSONHelpers.encodePretty(staleComment))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let review = model.surface().review

        XCTAssertEqual(review.files.count, 1)
        XCTAssertEqual(review.files.first?.comments.map(\.text), ["Check the public API name."])
        XCTAssertEqual(
            review.files.first?.hunkItems.first?.lines.first?.comments.map(\.text),
            ["This line should stay public.", "Keep the title next to the import."]
        )
        XCTAssertEqual(review.files.first?.hunkItems.first?.lines.first?.comments.last?.lineRangeLabel, "Lines 1-2")
    }

    func testGitDiffReviewSurfaceHidesStaleDiffWhenLatestDiffFailed() throws {
        let successfulCall = ToolCall(id: "git-diff-1", name: "host.git.diff", argumentsJSON: "{}")
        let failedCall = ToolCall(id: "git-diff-2", name: "host.git.diff", argumentsJSON: "{}")
        let successfulResult = ToolResult(ok: true, stdout: """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        @@ -1 +1 @@
        -old
        +new
        """)
        let failedResult = ToolResult(ok: false, error: "not a git repository")
        let thread = ChatThread(
            title: "Git diff",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(successfulCall)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(successfulResult)),
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(failedCall)),
                ThreadEvent(kind: .toolFailed, summary: "host.git.diff failed", payloadJSON: try JSONHelpers.encodePretty(failedResult))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertFalse(model.surface().review.isVisible)
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
