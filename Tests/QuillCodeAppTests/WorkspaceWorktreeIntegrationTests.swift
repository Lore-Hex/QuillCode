import Foundation
import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceWorktreeIntegrationTests: XCTestCase {
    func testWorkspaceCommandListsGitWorktrees() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Worktree Project")
        model.selectProject(projectID)

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-list", workspaceRoot: root))

        let cards = model.currentToolCards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, ToolDefinition.gitWorktreeList.name)
        XCTAssertEqual(cards[0].status, .done)
        let outputJSON = try XCTUnwrap(cards[0].outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.stdout.contains(root.standardizedFileURL.path), result.stdout)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
    }

    func testRemoteWorkspaceCommandListsGitWorktreesThroughSSH() throws {
        let fixture = try makeRemoteWorktreeFixture()

        XCTAssertTrue(fixture.model.runWorkspaceCommand("git-worktree-list", workspaceRoot: fixture.localRoot))

        let card = try XCTUnwrap(fixture.model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitWorktreeList.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.stdout.contains(fixture.remoteRoot.standardizedFileURL.path), result.stdout)
        XCTAssertTrue(try fixture.recordedSSHArguments().contains("git worktree list --porcelain"))
    }

    func testWorkspaceWorktreeCommandsPrefillComposer() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a git worktree named ")

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-open", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Open git worktree at ")

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-remove", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Remove git worktree at ")
    }

    func testWorkspaceOpenExistingWorktreeOpensFocusedThreadAndKeepsToolAudit() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let worktreeName = "quillcode-existing-\(UUID().uuidString)"
        let branch = "quillcode-existing-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let create = GitToolExecutor().createWorktree(cwd: root, path: worktreeName, branch: String(branch))
        XCTAssertTrue(create.ok, create.error ?? create.stderr)

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Worktree Project")
        let sourceThreadID = model.newChat(projectID: projectID)
        model.startSidebarSelection(selecting: sourceThreadID)

        model.openWorktree(.init(path: worktreeName), workspaceRoot: root)

        XCTAssertEqual(model.selectedProject?.path, worktree.path)
        XCTAssertEqual(model.selectedProject?.name, worktreeName)
        XCTAssertEqual(model.selectedThread?.projectID, model.selectedProject?.id)
        XCTAssertEqual(model.selectedThread?.title, "Worktree: \(worktreeName)")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Opened worktree `\(worktreeName)`") == true)
        XCTAssertEqual(model.root.topBar.projectName, worktreeName)

        let openCard = try XCTUnwrap(worktreeCard(in: model, title: ToolDefinition.gitWorktreeOpen.name))
        XCTAssertNotEqual(openCard.threadID, model.selectedThread?.id)
        XCTAssertEqual(openCard.card.status, .done)
        XCTAssertTrue(openCard.card.inputJSON?.contains(worktreeName) == true)
        XCTAssertEqual(model.selectedSidebarThreadIDs(), [])

        model.removeWorktree(.init(path: worktreeName), workspaceRoot: root)
    }

    func testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let worktreeName = "quillcode-ui-\(UUID().uuidString)"
        let branch = "quillcode-ui-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Worktree Project")
        let sourceThreadID = model.newChat(projectID: projectID)
        model.startSidebarSelection(selecting: sourceThreadID)
        XCTAssertEqual(model.selectedSidebarThreadIDs(), [sourceThreadID])

        model.createWorktree(.init(path: worktreeName, branch: String(branch)), workspaceRoot: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.selectedProject?.path, worktree.path)
        XCTAssertEqual(model.selectedProject?.name, worktreeName)
        XCTAssertEqual(model.selectedThread?.projectID, model.selectedProject?.id)
        XCTAssertEqual(model.selectedThread?.title, "Worktree: \(branch)")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Opened worktree `\(worktreeName)`") == true)
        XCTAssertEqual(model.root.topBar.projectName, worktreeName)
        XCTAssertEqual(model.root.topBar.threadTitle, "Worktree: \(branch)")

        let createCard = try XCTUnwrap(worktreeCard(in: model, title: ToolDefinition.gitWorktreeCreate.name))
        XCTAssertNotEqual(createCard.threadID, model.selectedThread?.id)
        XCTAssertEqual(createCard.card.status, .done)
        XCTAssertTrue(createCard.card.inputJSON?.contains(worktreeName) == true)
        XCTAssertEqual(model.selectedSidebarThreadIDs(), [])

        model.removeWorktree(.init(path: worktreeName), workspaceRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitWorktreeRemove.name)
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
    }

    func testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit() throws {
        let fixture = try makeRemoteWorktreeFixture()
        let parent = fixture.remoteRoot.deletingLastPathComponent()
        let worktreeName = "remote-ui-\(UUID().uuidString)"
        let branch = "remote-ui-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL

        fixture.model.createWorktree(
            .init(path: worktreeName, branch: String(branch)),
            workspaceRoot: fixture.localRoot
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(fixture.model.selectedProject?.connection.kind, .ssh)
        XCTAssertEqual(fixture.model.selectedProject?.connection.host, "feather.local")
        XCTAssertEqual(fixture.model.selectedProject?.connection.user, "quill")
        XCTAssertEqual(fixture.model.selectedProject?.connection.port, 2222)
        XCTAssertEqual(fixture.model.selectedProject?.connection.path, worktree.path)
        XCTAssertEqual(fixture.model.selectedThread?.projectID, fixture.model.selectedProject?.id)
        XCTAssertEqual(fixture.model.selectedThread?.title, "Worktree: \(branch)")
        XCTAssertTrue(fixture.model.selectedThread?.messages.last?.content.contains("Opened remote worktree `\(worktreeName)`") == true)
        XCTAssertEqual(fixture.model.root.topBar.projectName, "feather.local · \(worktreeName)")

        let createCard = try XCTUnwrap(worktreeCard(in: fixture.model, title: ToolDefinition.gitWorktreeCreate.name))
        XCTAssertNotEqual(createCard.threadID, fixture.model.selectedThread?.id)
        XCTAssertEqual(createCard.card.status, .done)
        let createResult = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(createCard.card.outputJSON))
        XCTAssertEqual(createResult.artifacts, ["ssh://quill@feather.local:2222\(worktree.path)"])
    }

    func testRemoteWorkspaceOpenExistingWorktreeOpensSSHProjectAndKeepsToolAudit() throws {
        let fixture = try makeRemoteWorktreeFixture()
        let parent = fixture.remoteRoot.deletingLastPathComponent()
        let worktreeName = "remote-existing-\(UUID().uuidString)"
        let branch = "remote-existing-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let create = GitToolExecutor().createWorktree(
            cwd: fixture.remoteRoot,
            path: worktreeName,
            branch: String(branch)
        )
        XCTAssertTrue(create.ok, create.error ?? create.stderr)

        fixture.model.openWorktree(.init(path: worktreeName), workspaceRoot: fixture.localRoot)

        XCTAssertEqual(fixture.model.selectedProject?.connection.kind, .ssh)
        XCTAssertEqual(fixture.model.selectedProject?.connection.path, worktree.path)
        XCTAssertEqual(fixture.model.selectedThread?.title, "Worktree: \(worktreeName)")
        XCTAssertTrue(fixture.model.selectedThread?.messages.last?.content.contains("Opened remote worktree `\(worktreeName)`") == true)

        let openCard = try XCTUnwrap(worktreeCard(in: fixture.model, title: ToolDefinition.gitWorktreeOpen.name))
        XCTAssertNotEqual(openCard.threadID, fixture.model.selectedThread?.id)
        XCTAssertEqual(openCard.card.status, .done)
        let openResult = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(openCard.card.outputJSON))
        XCTAssertEqual(openResult.artifacts, ["ssh://quill@feather.local:2222\(worktree.path)"])
        let sshArguments = try fixture.recordedSSHArguments()
        XCTAssertTrue(sshArguments.contains("printf 'worktree %s\\n'"), sshArguments)
    }

    private func makeRemoteWorktreeFixture() throws -> RemoteWorktreeFixture {
        let localRoot = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let argumentsFile = localRoot.appendingPathComponent("ssh-agent-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: localRoot, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )
        return RemoteWorktreeFixture(
            localRoot: localRoot,
            remoteRoot: remoteRoot,
            argumentsFile: argumentsFile,
            model: model
        )
    }

    private func worktreeCard(
        in model: QuillCodeWorkspaceModel,
        title: String
    ) -> (threadID: UUID, card: ToolCardState)? {
        for thread in model.root.threads {
            let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()
            if let card = cards.last(where: { $0.title == title }) {
                return (thread.id, card)
            }
        }
        return nil
    }
}

private struct RemoteWorktreeFixture {
    var localRoot: URL
    var remoteRoot: URL
    var argumentsFile: URL
    var model: QuillCodeWorkspaceModel

    func recordedSSHArguments() throws -> String {
        try String(contentsOf: argumentsFile, encoding: .utf8)
    }
}
