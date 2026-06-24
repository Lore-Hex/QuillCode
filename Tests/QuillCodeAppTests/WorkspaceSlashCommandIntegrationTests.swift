import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceSlashCommandIntegrationTests: XCTestCase {
    func testCommandPaletteSlashCommandPrefillsComposer() throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        let command = try XCTUnwrap(
            WorkspaceCommandPalette.rankedCommands(model.surface().commands, matching: "/mode").first
        )

        XCTAssertTrue(model.runWorkspaceCommand(command.id, workspaceRoot: root))

        XCTAssertEqual(model.composer.draft, "/mode ")
    }

    func testSlashCommandsRouteToWorkspaceActions() async throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Project")
        model.selectProject(projectID)

        model.setDraft("/terminal")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertTrue(model.terminal.isVisible)

        await model.runTerminalCommand("printf slash-clear", workspaceRoot: root)
        XCTAssertFalse(model.terminal.entries.isEmpty)
        model.setDraft("/terminal clear")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertTrue(model.terminal.entries.isEmpty)
        XCTAssertTrue(model.terminal.isVisible)

        model.setDraft("/browser")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertTrue(model.browser.isVisible)

        model.setDraft("/worktrees")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.list")

        model.setDraft("/pr")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        model.setDraft("/project rename Slash Renamed")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedProject?.name, "Slash Renamed")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Renamed project to Slash Renamed.")

        model.setDraft("/project new")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
    }

    func testSlashEnvironmentActionListsAndRunsByName() async throws {
        let setup = try makeProjectWithLocalEnvironmentAction(
            scriptName: "bootstrap-env.sh",
            scriptContents: "printf slash-env-ok"
        )

        setup.model.setDraft("/env")
        await setup.model.submitComposer(workspaceRoot: setup.root)
        XCTAssertEqual(setup.model.selectedThread?.title, "Local environment actions")
        XCTAssertTrue(setup.model.selectedThread?.messages.last?.content.contains("/env Bootstrap Env") == true)

        setup.model.setDraft("/env bootstrap env")
        await setup.model.submitComposer(workspaceRoot: setup.root)

        let card = try XCTUnwrap(setup.model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.shell.run")
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertEqual(result.stdout, "slash-env-ok")
    }

    func testSlashEnvironmentActionListShowsMetadataDescription() async throws {
        let setup = try makeProjectWithLocalEnvironmentAction(
            scriptName: "prepare.sh",
            scriptContents: "printf metadata-env-ok",
            metadataJSON: """
            {
              "title": "Prepare Workspace",
              "description": "Install dependencies and warm caches."
            }
            """
        )

        setup.model.setDraft("/env")
        await setup.model.submitComposer(workspaceRoot: setup.root)

        let message = try XCTUnwrap(setup.model.selectedThread?.messages.last?.content)
        XCTAssertTrue(message.contains("/env Prepare Workspace"))
        XCTAssertTrue(message.contains("Install dependencies and warm caches."))
    }

    func testSlashNewCreatesFreshThreadWithoutAgentRun() async throws {
        let existing = ChatThread(title: "Existing")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [existing],
            selectedThreadID: existing.id
        ))

        model.setDraft("/new")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        XCTAssertEqual(model.composer.draft, "")
        XCTAssertEqual(model.root.threads.count, 2)
        XCTAssertEqual(model.selectedThread?.title, "New chat")
        XCTAssertTrue(model.selectedThread?.messages.isEmpty == true)
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashModeChangesModeAndWritesLocalTranscript() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/mode review")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        XCTAssertEqual(model.root.config.mode, .review)
        XCTAssertEqual(model.selectedThread?.mode, .review)
        XCTAssertEqual(model.selectedThread?.title, "Set mode")
        XCTAssertEqual(model.selectedThread?.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Mode set to Review.")
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashModelChangesModelAndWritesLocalTranscript() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/model z-ai/glm-5.2")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        XCTAssertEqual(model.root.config.defaultModel, "z-ai/glm-5.2")
        XCTAssertEqual(model.selectedThread?.model, "z-ai/glm-5.2")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Model set to z-ai/glm-5.2.")
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashModelLegacyFusionAliasWritesPreferredSynthTranscript() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/model /fusion")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        XCTAssertEqual(model.root.config.defaultModel, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(model.selectedThread?.model, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Model set to Synth (/synth).")
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashCompactRoutesToContextCompaction() async throws {
        let source = ChatThread(title: "Long slash thread", messages: [
            .init(role: .user, content: "old question"),
            .init(role: .assistant, content: "old answer"),
            .init(role: .user, content: "latest question"),
            .init(role: .assistant, content: "latest answer")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))

        model.setDraft("/compact")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        XCTAssertEqual(model.selectedThread?.title, "Compact: Long slash thread")
        XCTAssertEqual(Array(model.selectedThread?.messages.map(\.content).suffix(2) ?? []), ["latest question", "latest answer"])
        XCTAssertTrue(model.selectedThread?.messages.first?.content.contains("Context compacted") == true)
    }

    func testSlashThreadLifecycleCommands() async throws {
        let source = ChatThread(title: "Original", messages: [
            .init(role: .user, content: "run whoami")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))
        let root = try makeQuillCodeTestDirectory()

        model.setDraft("/rename Better name")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.title, "Better name")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Renamed chat to Better name.")

        model.setDraft("/duplicate")
        await model.submitComposer(workspaceRoot: root)
        let duplicateID = try XCTUnwrap(model.root.selectedThreadID)
        XCTAssertEqual(model.selectedThread?.title, "Copy: Better name")

        model.setDraft("/archive")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.root.selectedThreadID, source.id)
        XCTAssertTrue(model.root.threads.first { $0.id == duplicateID }?.isArchived == true)

        model.selectThread(duplicateID)
        model.setDraft("/unarchive")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)
        XCTAssertFalse(model.selectedThread?.isArchived ?? true)
    }

    func testSlashStatusReportsWorkspaceState() async throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Status thread", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.setDraft("/status")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        let message = try XCTUnwrap(model.selectedThread?.messages.last?.content)
        XCTAssertTrue(message.contains("Project: QuillCode"))
        XCTAssertTrue(message.contains("Thread: Status thread"))
        XCTAssertTrue(message.contains("Mode: Auto"))
        XCTAssertTrue(message.contains("Model: trustedrouter/fast"))
    }

    private func makeProjectWithLocalEnvironmentAction(
        scriptName: String,
        scriptContents: String,
        metadataJSON: String? = nil
    ) throws -> (root: URL, model: QuillCodeWorkspaceModel) {
        let root = try makeQuillCodeTestDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try scriptContents.write(
            to: actionsDirectory.appendingPathComponent(scriptName),
            atomically: true,
            encoding: .utf8
        )
        if let metadataJSON {
            try metadataJSON.write(
                to: actionsDirectory.appendingPathComponent(scriptName.replacingOccurrences(of: ".sh", with: ".json")),
                atomically: true,
                encoding: .utf8
            )
        }

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Project")
        model.selectProject(projectID)
        return (root, model)
    }

}
