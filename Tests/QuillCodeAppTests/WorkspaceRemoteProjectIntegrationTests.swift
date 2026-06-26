import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceRemoteProjectIntegrationTests: XCTestCase {
    func testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/ssh quill@feather.local:/srv/quill")
        await model.submitComposer(workspaceRoot: URL(fileURLWithPath: "/tmp/local"))

        let project = try XCTUnwrap(model.selectedProject)
        XCTAssertEqual(project.name, "feather.local · quill")
        XCTAssertEqual(project.connection, .ssh(path: "/srv/quill", host: "feather.local", user: "quill"))
        XCTAssertEqual(project.displayPath, "ssh://quill@feather.local/srv/quill")
        XCTAssertTrue(project.isRemote)
        XCTAssertNil(model.activeWorkspaceRoot)
        XCTAssertEqual(model.terminal.currentDirectoryPath, "ssh://quill@feather.local/srv/quill")

        let surface = model.surface()
        XCTAssertEqual(surface.terminal.cwdLabel, "ssh://quill@feather.local/srv/quill")
        XCTAssertEqual(surface.projects.items.first?.connectionKindLabel, "SSH Remote")
        XCTAssertEqual(surface.projects.items.first?.actions.first { $0.kind == .refreshContext }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-view" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checks" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-diff" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checkout" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-reviewers" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-comment" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review-comment" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-labels" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-merge" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-list" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-open" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-remove" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-prune" }?.isEnabled, true)
        XCTAssertEqual(model.selectedThread?.messages.last?.content.contains("Added SSH Remote"), true)
        XCTAssertEqual(model.selectedThread?.messages.last?.content.contains("PR checkout/reviewers/labels/merge"), true)
    }

    func testRefreshProjectContextLoadsSSHRemoteInstructionsAndMemories() throws {
        let root = try makeTempDirectory()
        let remoteRoot = root.appendingPathComponent("remote repo")
        try FileManager.default.createDirectory(
            at: remoteRoot.appendingPathComponent(".quillcode/memories"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: remoteRoot.appendingPathComponent("Sources/Feature"),
            withIntermediateDirectories: true
        )
        try "Root agent rules".write(
            to: remoteRoot.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Remote project rules".write(
            to: remoteRoot.appendingPathComponent(".quillcode/rules.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Feature-scoped rules".write(
            to: remoteRoot.appendingPathComponent("Sources/Feature/AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Prefer short final answers.".write(
            to: remoteRoot.appendingPathComponent(".quillcode/memories/team-note.md"),
            atomically: true,
            encoding: .utf8
        )

        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill"
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )
        _ = model.newChat(projectID: project.id)

        XCTAssertTrue(model.refreshProjectContext(project.id), model.lastError ?? "")

        let refreshedProject = try XCTUnwrap(model.root.projects.first)
        XCTAssertEqual(
            refreshedProject.instructions.map(\.path),
            ["AGENTS.md", ".quillcode/rules.md", "Sources/Feature/AGENTS.md"]
        )
        XCTAssertEqual(refreshedProject.instructions.map(\.content), [
            "Root agent rules",
            "Remote project rules",
            "Feature-scoped rules"
        ])
        XCTAssertEqual(refreshedProject.memories.map(\.relativePath), [".quillcode/memories/team-note.md"])
        XCTAssertEqual(refreshedProject.memories.first?.title, "Team Note")
        XCTAssertEqual(refreshedProject.memories.first?.content, "Prefer short final answers.")
        XCTAssertEqual(model.selectedThread?.instructions.map(\.path), refreshedProject.instructions.map(\.path))
        XCTAssertEqual(model.selectedThread?.memories.map(\.relativePath), refreshedProject.memories.map(\.relativePath))
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Refreshed project context")

        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("cd '\(remoteRoot.path.replacingOccurrences(of: "'", with: "'\\''"))' &&"))
        XCTAssertTrue(arguments.contains("QUILLCODE_CONTEXT_"))
    }

    func testSlashSSHRejectsMalformedAddress() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/ssh feather.local relative/path")
        await model.submitComposer(workspaceRoot: URL(fileURLWithPath: "/tmp/local"))

        XCTAssertTrue(model.root.projects.isEmpty)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Use SSH format user@host:/path or ssh://user@host/path."
        )
    }

    func testRemoteProjectAgentOffersOnlyRemoteSafeBaseTools() async throws {
        let root = try makeTempDirectory()
        let connection = ProjectConnection.ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let recorder = ToolDefinitionRecorder()
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            runner: AgentRunner(llm: RecordingLLMClient(recorder: recorder))
        )

        model.setDraft("What can you do here?")
        await model.submitComposer(workspaceRoot: root)

        let toolNames = Set(recorder.tools.map(\.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.shellRun.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.fileRead.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.fileWrite.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.applyPatch.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitStatus.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitDiff.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitStage.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitRestore.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitStageHunk.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitRestoreHunk.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitCommit.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPush.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestCreate.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestView.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestChecks.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestCheckout.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestReviewers.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestLabels.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestComment.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestReview.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestReviewComment.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitPullRequestMerge.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitWorktreeList.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitWorktreeCreate.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitWorktreeOpen.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitWorktreeRemove.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.gitWorktreePrune.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.planUpdate.name))
        XCTAssertTrue(toolNames.contains(ToolDefinition.browserInspect.name))
    }
}
