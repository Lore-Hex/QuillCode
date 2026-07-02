import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceRemoteProjectToolExecutorTests: XCTestCase {
    func testToolDefinitionsExposeRemoteSafeWorkspaceTools() {
        let names = Set(WorkspaceRemoteProjectToolExecutor.toolDefinitions.map(\.name))

        XCTAssertTrue(names.contains(ToolDefinition.shellRun.name))
        XCTAssertTrue(names.contains(ToolDefinition.fileRead.name))
        XCTAssertTrue(names.contains(ToolDefinition.fileList.name))
        XCTAssertTrue(names.contains(ToolDefinition.fileWrite.name))
        XCTAssertTrue(names.contains(ToolDefinition.applyPatch.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitStatus.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitPullRequestList.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitPullRequestCreate.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitPullRequestLifecycle.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitPullRequestReviewComment.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitPullRequestReviewReply.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitPullRequestReviewThreads.name))
        XCTAssertTrue(names.contains(ToolDefinition.gitPullRequestReviewThread.name))
        XCTAssertFalse(names.contains(ToolDefinition.browserInspect.name))
        XCTAssertFalse(names.contains(ToolDefinition.planUpdate.name))
    }

    func testExecutionOverrideRequiresRemoteProject() {
        let local = ProjectRef(name: "Local", path: "/tmp/quillcode")

        XCTAssertNil(WorkspaceRemoteProjectToolExecutor.executionOverride(
            project: local,
            executor: SSHRemoteShellExecutor()
        ))
        XCTAssertNil(WorkspaceRemoteProjectToolExecutor.executionOverride(
            project: nil,
            executor: SSHRemoteShellExecutor()
        ))
    }

    func testRunsRemoteShellThroughSSH() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let project = remoteProject(path: "/srv/quill repo")

        let result = WorkspaceRemoteProjectToolExecutor.execute(
            ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "pwd"])
            ),
            project: project,
            executor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path, connectTimeoutSeconds: 4)
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "remote-ok\n")
        let arguments = try recordedArguments(from: argumentsFile)
        XCTAssertEqual(arguments, [
            "-T",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=4",
            "-p",
            "2222",
            "--",
            "quill@feather.local",
            "cd '/srv/quill repo' && pwd"
        ])
    }

    func testRemoteFileWriteAddsRemoteArtifact() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let project = remoteProject(path: "/srv/quill")

        let result = WorkspaceRemoteProjectToolExecutor.execute(
            ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "notes/hello.txt",
                    "content": "hello world\n"
                ])
            ),
            project: project,
            executor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.artifacts, ["ssh://quill@feather.local:2222/srv/quill/notes/hello.txt"])
        let command = try recordedArguments(from: argumentsFile).last ?? ""
        XCTAssertTrue(command.contains("mkdir -p -- 'notes'"), command)
        XCTAssertTrue(command.contains("base64 --decode > 'notes/hello.txt'"), command)
    }

    func testRemoteFileListReturnsStructuredBoundedOutput() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempDirectory()
        try FileManager.default.createDirectory(
            at: remoteRoot.appendingPathComponent("docs/nested"),
            withIntermediateDirectories: true
        )
        try "visible\n".write(
            to: remoteRoot.appendingPathComponent("docs/visible.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "secret\n".write(
            to: remoteRoot.appendingPathComponent("docs/.env"),
            atomically: true,
            encoding: .utf8
        )
        let argumentsFile = root.appendingPathComponent("ssh-list-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)

        let result = WorkspaceRemoteProjectToolExecutor.execute(
            ToolCall(
                name: ToolDefinition.fileList.name,
                argumentsJSON: ToolArguments.json([
                    "path": "docs",
                    "includeHidden": true,
                    "maxEntries": 1
                ])
            ),
            project: remoteProject(path: remoteRoot.path),
            executor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONDecoder().decode(FileListToolOutput.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(output.path, "docs")
        XCTAssertEqual(output.totalEntries, 3)
        XCTAssertTrue(output.includedHidden)
        XCTAssertTrue(output.truncated)
        XCTAssertEqual(output.entries.map(\.path), ["docs/nested"])
        XCTAssertEqual(output.entries.first?.kind, "directory")
        XCTAssertEqual(result.artifacts, ["ssh://quill@feather.local:2222\(remoteRoot.path)/docs/nested"])

        XCTAssertTrue(FileManager.default.fileExists(atPath: argumentsFile.path))
    }

    func testRemoteFileListRejectsUnsafePathBeforeSSH() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-unsafe-list-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)

        let result = WorkspaceRemoteProjectToolExecutor.execute(
            ToolCall(
                name: ToolDefinition.fileList.name,
                argumentsJSON: ToolArguments.json(["path": "../escape"])
            ),
            project: remoteProject(path: remoteRoot.path),
            executor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("outside the workspace") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: argumentsFile.path))
    }

    func testRemoteGitPlannerBuildsPullRequestCreateRequest() throws {
        let listRequest = try WorkspaceRemoteGitToolRequestPlanner.request(
            for: ToolCall(
                name: ToolDefinition.gitPullRequestList.name,
                argumentsJSON: ToolArguments.json(["state": "all", "limit": 20])
            ),
            connection: remoteProject(path: "/srv/quill").connection
        )

        XCTAssertEqual(listRequest.command, "'gh' 'pr' 'list' '--state' 'all' '--limit' '20'")
        XCTAssertEqual(listRequest.artifacts, [])
        XCTAssertTrue(listRequest.extractsPullRequestURLs)

        let request = try WorkspaceRemoteGitToolRequestPlanner.request(
            for: ToolCall(
                name: ToolDefinition.gitPullRequestCreate.name,
                argumentsJSON: ToolArguments.json([
                    "title": "Ship it",
                    "body": "Ready for review",
                    "base": "main",
                    "head": "feature/quill",
                    "draft": true
                ])
            ),
            connection: remoteProject(path: "/srv/quill").connection
        )

        XCTAssertEqual(
            request.command,
            "'gh' 'pr' 'create' '--title' 'Ship it' '--body' 'Ready for review' '--base' 'main' '--head' 'feature/quill' '--draft'"
        )
        XCTAssertEqual(request.artifacts, [])
        XCTAssertTrue(request.extractsPullRequestURLs)
    }

    func testRemoteGitBasicBuilderBuildsCommonCommands() throws {
        XCTAssertEqual(
            try remoteBasicGitCommand(name: ToolDefinition.gitStatus.name, arguments: [:]),
            "git status --short --branch"
        )
        XCTAssertEqual(
            try remoteBasicGitCommand(name: ToolDefinition.gitDiff.name, arguments: ["staged": true]),
            "git diff --staged"
        )
        XCTAssertEqual(
            try remoteBasicGitCommand(name: ToolDefinition.gitStage.name, arguments: ["path": "notes/plan.txt"]),
            "git add -- 'notes/plan.txt'"
        )
        XCTAssertEqual(
            try remoteBasicGitCommand(name: ToolDefinition.gitRestore.name, arguments: [
                "path": "notes/plan.txt",
                "staged": true
            ]),
            "git restore --staged -- 'notes/plan.txt'"
        )
        XCTAssertEqual(
            try remoteBasicGitCommand(name: ToolDefinition.gitCommit.name, arguments: ["message": " Ship it "]),
            "git commit -m 'Ship it'"
        )
    }

    func testRemoteGitBasicBuilderRejectsUnsafeInputs() {
        XCTAssertThrowsError(
            try remoteBasicGitCommand(name: ToolDefinition.gitStage.name, arguments: ["path": "../outside.txt"])
        )
        XCTAssertThrowsError(
            try remoteBasicGitCommand(name: ToolDefinition.gitCommit.name, arguments: ["message": "  \n"])
        )
    }

    func testRemoteGitHubPullRequestBuilderBuildsReviewAndMergeCommands() throws {
        let lifecycleCommand = try remotePullRequestCommand(
            name: ToolDefinition.gitPullRequestLifecycle.name,
            arguments: ["selector": "42", "action": "close"]
        )
        XCTAssertEqual(lifecycleCommand, "'gh' 'pr' 'close' '42'")

        let reviewCommand = try remotePullRequestCommand(
            name: ToolDefinition.gitPullRequestReview.name,
            arguments: [
                "selector": "42",
                "action": "request-changes",
                "body": "Needs the smoke run first."
            ]
        )
        XCTAssertEqual(
            reviewCommand,
            "'gh' 'pr' 'review' '42' '--request-changes' '--body' 'Needs the smoke run first.'"
        )

        let mergeCommand = try remotePullRequestCommand(
            name: ToolDefinition.gitPullRequestMerge.name,
            arguments: [
                "selector": "42",
                "method": "rebase",
                "auto": true,
                "deleteBranch": true
            ]
        )
        XCTAssertEqual(mergeCommand, "'gh' 'pr' 'merge' '42' '--rebase' '--auto' '--delete-branch'")
    }

    func testRemoteGitHubPullRequestBuilderBuildsInlineReviewCommentCommand() throws {
        let command = try remotePullRequestCommand(
            name: ToolDefinition.gitPullRequestReviewComment.name,
            arguments: [
                "selector": "42",
                "path": "Sources/App.swift",
                "line": 12,
                "body": "Please cover this branch."
            ]
        )

        XCTAssertEqual(
            command,
            [
                "pr_data=$('gh' 'pr' 'view' '42' '--json' 'number,headRefOid' '--jq' '.number + \" \" + .headRefOid')",
                "pr_number=${pr_data%% *}",
                "head_oid=${pr_data#* }",
                "repo=$('gh' 'repo' 'view' '--json' 'nameWithOwner' '--jq' '.nameWithOwner')",
                "gh api \"repos/${repo}/pulls/${pr_number}/comments\" '--raw-field' 'body=Please cover this branch.' '--raw-field' \"commit_id=${head_oid}\" '--raw-field' 'path=Sources/App.swift' '--field' 'line=12' '--raw-field' 'side=RIGHT'"
            ].joined(separator: " && ")
        )
    }

    func testRemoteGitHubPullRequestBuilderBuildsReviewReplyCommand() throws {
        let command = try remotePullRequestCommand(
            name: ToolDefinition.gitPullRequestReviewReply.name,
            arguments: [
                "selector": "42",
                "commentId": 99,
                "body": "Updated this, thanks."
            ]
        )

        XCTAssertEqual(
            command,
            [
                "pr_number=$('gh' 'pr' 'view' '42' '--json' 'number' '--jq' '.number')",
                "repo=$('gh' 'repo' 'view' '--json' 'nameWithOwner' '--jq' '.nameWithOwner')",
                "gh api \"repos/${repo}/pulls/${pr_number}/comments/99/replies\" '--raw-field' 'body=Updated this, thanks.'"
            ].joined(separator: " && ")
        )
    }

    func testRemoteGitHubPullRequestBuilderBuildsReviewThreadsCommand() throws {
        let command = try remotePullRequestCommand(
            name: ToolDefinition.gitPullRequestReviewThreads.name,
            arguments: ["selector": "42"]
        )

        XCTAssertTrue(command.contains("'gh' 'pr' 'view' '42' '--json' 'number' '--jq' '.number'"), command)
        XCTAssertTrue(command.contains("'gh' 'repo' 'view' '--json' 'nameWithOwner' '--jq' '.nameWithOwner'"), command)
        XCTAssertTrue(command.contains("owner=${repo%%/*}"), command)
        XCTAssertTrue(command.contains("name=${repo#*/}"), command)
        XCTAssertTrue(command.contains("gh api graphql"), command)
        XCTAssertTrue(command.contains("\"number=${pr_number}\""), command)
        XCTAssertTrue(command.contains("reviewThreads(first: 50)"), command)
        XCTAssertTrue(command.contains("databaseId"), command)
    }

    func testRemoteGitHubPullRequestBuilderBuildsReviewThreadCommand() throws {
        let command = try remotePullRequestCommand(
            name: ToolDefinition.gitPullRequestReviewThread.name,
            arguments: [
                "threadId": "PRRT_kwDOExample",
                "action": "resolve"
            ]
        )

        XCTAssertEqual(
            command,
            "'gh' 'api' 'graphql' '--raw-field' 'threadId=PRRT_kwDOExample' '--raw-field' 'query=mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { id isResolved } } }'"
        )
    }

    func testRemoteGitHubPullRequestBuilderUsesSharedValidation() {
        XCTAssertThrowsError(
            try remotePullRequestCommand(
                name: ToolDefinition.gitPullRequestView.name,
                arguments: ["selector": "--bad"]
            )
        )

        XCTAssertThrowsError(
            try remotePullRequestCommand(
                name: ToolDefinition.gitPullRequestComment.name,
                arguments: ["body": "   "]
            )
        )
    }

    func testRemoteGitPlannerBuildsPullRequestChecksWithoutURLExtraction() throws {
        let request = try WorkspaceRemoteGitToolRequestPlanner.request(
            for: ToolCall(
                name: ToolDefinition.gitPullRequestChecks.name,
                argumentsJSON: ToolArguments.json(["selector": "42"])
            ),
            connection: remoteProject(path: "/srv/quill").connection
        )

        XCTAssertEqual(request.command, "'gh' 'pr' 'checks' '42'")
        XCTAssertEqual(request.artifacts, [])
        XCTAssertFalse(request.extractsPullRequestURLs)
    }

    func testRemoteGitPlannerBuildsWorktreeCreateRequestWithArtifact() throws {
        let request = try WorkspaceRemoteGitToolRequestPlanner.request(
            for: ToolCall(
                name: ToolDefinition.gitWorktreeCreate.name,
                argumentsJSON: ToolArguments.json([
                    "path": "quill-next",
                    "branch": "codex/next",
                    "base": "origin/main"
                ])
            ),
            connection: remoteProject(path: "/srv/quill").connection
        )

        XCTAssertEqual(
            request.command,
            "'git' 'worktree' 'add' '-b' 'codex/next' '/srv/quill-next' 'origin/main'"
        )
        XCTAssertEqual(request.artifacts, ["ssh://quill@feather.local:2222/srv/quill-next"])
        XCTAssertFalse(request.extractsPullRequestURLs)
    }

    func testRemoteGitWorktreeBuilderBuildsListOpenAndRemovePlans() throws {
        let listPlan = try remoteWorktreePlan(
            name: ToolDefinition.gitWorktreeList.name,
            arguments: [:],
            connection: remoteProject(path: "/srv/quill").connection
        )
        XCTAssertEqual(listPlan.command, "git worktree list --porcelain")
        XCTAssertEqual(listPlan.artifacts, [])

        let openPlan = try remoteWorktreePlan(
            name: ToolDefinition.gitWorktreeOpen.name,
            arguments: ["path": "quill-next"],
            connection: remoteProject(path: "/srv/quill").connection
        )
        XCTAssertTrue(openPlan.command.contains("worktree='/srv/quill-next'"), openPlan.command)
        XCTAssertTrue(openPlan.command.contains("printf 'worktree %s\\n' \"$worktree\""), openPlan.command)
        XCTAssertEqual(openPlan.artifacts, ["ssh://quill@feather.local:2222/srv/quill-next"])

        let removePlan = try remoteWorktreePlan(
            name: ToolDefinition.gitWorktreeRemove.name,
            arguments: [
                "path": "quill-next",
                "force": true
            ],
            connection: remoteProject(path: "/srv/quill").connection
        )
        XCTAssertTrue(removePlan.command.contains("worktree='/srv/quill-next'"), removePlan.command)
        XCTAssertTrue(removePlan.command.contains("git worktree remove --force -- \"$worktree\""), removePlan.command)
        XCTAssertEqual(removePlan.artifacts, [])

        let prunePlan = try remoteWorktreePlan(
            name: ToolDefinition.gitWorktreePrune.name,
            arguments: [
                "dryRun": true,
                "verbose": true
            ],
            connection: remoteProject(path: "/srv/quill").connection
        )
        XCTAssertEqual(prunePlan.command, "'git' 'worktree' 'prune' '--dry-run' '--verbose'")
        XCTAssertEqual(prunePlan.artifacts, [])
    }

    func testRemoteGitPlannerBuildsStageHunkRequestWithSharedPatchValidation() throws {
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +new
        """

        let request = try WorkspaceRemoteGitToolRequestPlanner.request(
            for: ToolCall(
                name: ToolDefinition.gitStageHunk.name,
                argumentsJSON: ToolArguments.json([
                    "path": "hello.txt",
                    "patch": patch
                ])
            ),
            connection: remoteProject(path: "/srv/quill").connection
        )

        XCTAssertTrue(request.command.contains("quillcode-hunk.$$.patch"), request.command)
        XCTAssertTrue(request.command.contains("git apply '--cached' '--whitespace=nowarn' --check"), request.command)
        XCTAssertTrue(request.command.contains("printf 'Hunk staged.\\n'"), request.command)
        XCTAssertEqual(request.artifacts, [])
        XCTAssertFalse(request.extractsPullRequestURLs)
    }

    func testRemoteGitPushBuilderBuildsExplicitAndCurrentBranchCommands() throws {
        let explicitCommand = try remotePushCommand(arguments: [
            "remote": "origin",
            "branch": "codex/ship",
            "setUpstream": true
        ])
        XCTAssertEqual(explicitCommand, "git push -u 'origin' 'codex/ship'")

        let currentBranchCommand = try remotePushCommand(arguments: [:])
        XCTAssertTrue(currentBranchCommand.contains("branch=$(git branch --show-current)"), currentBranchCommand)
        XCTAssertTrue(currentBranchCommand.contains("test -n \"$branch\""), currentBranchCommand)
        XCTAssertTrue(currentBranchCommand.contains("case \"$branch\" in -*|*..*|*[!\(GitInputValidator.safeNameCharacters)]*)"), currentBranchCommand)
        XCTAssertTrue(currentBranchCommand.contains("git push 'origin' \"$branch\""), currentBranchCommand)
    }

    func testRemoteGitHunkBuilderBuildsRestoreCommandAndRejectsEmptyPatch() throws {
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let command = try remoteHunkCommand(
            name: ToolDefinition.gitRestoreHunk.name,
            arguments: [
                "path": "hello.txt",
                "patch": patch
            ]
        )

        XCTAssertTrue(command.contains("quillcode-hunk.$$.patch"), command)
        XCTAssertTrue(command.contains("git apply '--reverse' '--whitespace=nowarn' --check"), command)
        XCTAssertTrue(command.contains("printf 'Hunk restored.\\n'"), command)

        XCTAssertThrowsError(
            try remoteHunkCommand(
                name: ToolDefinition.gitStageHunk.name,
                arguments: [
                    "path": "hello.txt",
                    "patch": "   "
                ]
            )
        )
    }

    func testRemoteGitPlannerRejectsUnsafeWorktreeBranchAndBaseNames() {
        XCTAssertThrowsError(
            try WorkspaceRemoteGitToolRequestPlanner.request(
                for: ToolCall(
                    name: ToolDefinition.gitWorktreeCreate.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "quill-next",
                        "branch": "--bad"
                    ])
                ),
                connection: remoteProject(path: "/srv/quill").connection
            )
        )

        XCTAssertThrowsError(
            try WorkspaceRemoteGitToolRequestPlanner.request(
                for: ToolCall(
                    name: ToolDefinition.gitWorktreeCreate.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "quill-next",
                        "base": "../main"
                    ])
                ),
                connection: remoteProject(path: "/srv/quill").connection
            )
        )
    }

    func testRemoteGitPlannerRejectsWorktreeOutsideRemoteWorkspaceParent() {
        XCTAssertThrowsError(
            try WorkspaceRemoteGitToolRequestPlanner.request(
                for: ToolCall(
                    name: ToolDefinition.gitWorktreeCreate.name,
                    argumentsJSON: ToolArguments.json(["path": "../escape"])
                ),
                connection: remoteProject(path: "/srv/quill").connection
            )
        )
    }

    func testUnsupportedRemoteToolReturnsClearError() {
        let result = WorkspaceRemoteProjectToolExecutor.execute(
            ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
            project: remoteProject(path: "/srv/quill"),
            executor: SSHRemoteShellExecutor()
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Tool is not available for SSH Remote projects: \(ToolDefinition.browserInspect.name)"
        )
    }

    private func remoteBasicGitCommand(name: String, arguments: [String: Any]) throws -> String {
        let argumentsJSON = ToolArguments.json(arguments)
        let call = ToolCall(name: name, argumentsJSON: argumentsJSON)
        return try WorkspaceRemoteGitBasicCommandBuilder.command(
            for: call,
            arguments: try ToolArguments(argumentsJSON)
        )
    }

    private func remotePullRequestCommand(name: String, arguments: [String: Any]) throws -> String {
        let argumentsJSON = ToolArguments.json(arguments)
        return try WorkspaceRemoteGitHubPullRequestCommandBuilder.command(
            for: ToolCall(name: name, argumentsJSON: argumentsJSON),
            arguments: try ToolArguments(argumentsJSON)
        )
    }

    private func remoteWorktreePlan(
        name: String,
        arguments: [String: Any],
        connection: ProjectConnection
    ) throws -> WorkspaceRemoteGitWorktreePlan {
        let argumentsJSON = ToolArguments.json(arguments)
        return try WorkspaceRemoteGitWorktreeCommandBuilder.plan(
            for: ToolCall(name: name, argumentsJSON: argumentsJSON),
            arguments: try ToolArguments(argumentsJSON),
            connection: connection
        )
    }

    private func remoteHunkCommand(name: String, arguments: [String: Any]) throws -> String {
        let argumentsJSON = ToolArguments.json(arguments)
        return try WorkspaceRemoteGitHunkCommandBuilder.command(
            for: ToolCall(name: name, argumentsJSON: argumentsJSON),
            arguments: try ToolArguments(argumentsJSON)
        )
    }

    private func remotePushCommand(arguments: [String: Any]) throws -> String {
        let argumentsJSON = ToolArguments.json(arguments)
        return try WorkspaceRemoteGitPushCommandBuilder.command(arguments: try ToolArguments(argumentsJSON))
    }

    private func remoteProject(path: String) -> ProjectRef {
        let connection = ProjectConnection.ssh(
            path: path,
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        return ProjectRef(name: "Feather", path: connection.path, connection: connection)
    }

    private func makeFakeSSH(in root: URL, argumentsFile: URL) throws -> URL {
        let fakeSSH = root.appendingPathComponent("ssh")
        let script = """
        #!/bin/sh
        : > "\(argumentsFile.path)"
        for arg in "$@"; do
          printf '%s\\n' "$arg" >> "\(argumentsFile.path)"
        done
        printf 'remote-ok\\n'
        """
        try script.write(to: fakeSSH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)
        return fakeSSH
    }

    private func recordedArguments(from file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }
}
