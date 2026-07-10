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

        let previewFile = root.appendingPathComponent("slash-preview.html")
        try "<!doctype html><title>Slash Preview</title><h1>Slash Browser</h1>"
            .write(to: previewFile, atomically: true, encoding: .utf8)
        model.setDraft("/browser slash-preview.html")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.browser.currentURL, previewFile.standardizedFileURL.resolvingSymlinksInPath().absoluteString)
        XCTAssertEqual(model.browser.title, "Slash Preview")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Opened browser preview for Slash Preview at \(try XCTUnwrap(model.browser.currentURL)).")

        model.setDraft("/session localhost:5173")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.browser.currentURL, "http://localhost:5173")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Opened browser session for localhost at http://localhost:5173.")

        model.setDraft("/session")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Opened browser session for localhost at http://localhost:5173.")

        model.setDraft("/preview not-a-valid-target")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.browser.status, "Invalid address")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Enter an http, https, file, localhost, or project file URL.")

        model.setDraft("/worktrees")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.list")

        model.setDraft("/worktree prune --dry-run --verbose")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.prune")
        let pruneArguments = try ToolArguments(XCTUnwrap(model.currentToolCards.last?.inputJSON))
        XCTAssertEqual(pruneArguments.bool("dryRun"), true)
        XCTAssertEqual(pruneArguments.bool("verbose"), true)

        model.setDraft("/pr")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        model.setDraft("/project rename Slash Renamed")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedProject?.name, "Slash Renamed")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Renamed project to Slash Renamed.")

        model.setDraft("/project list")
        await model.submitComposer(workspaceRoot: root)
        let projectListMessage = try XCTUnwrap(model.selectedThread?.messages.last?.content)
        XCTAssertTrue(projectListMessage.contains("Projects:\n- Slash Renamed"))
        XCTAssertTrue(projectListMessage.contains("selected, Local"))
        XCTAssertTrue(projectListMessage.contains(root.path))

        model.setDraft("/project new")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
    }

    func testSlashWorktreeCreateOpenAndRemoveUseTypedWorktreeFlow() async throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let worktreeName = "slash-worktree-\(UUID().uuidString)"
        let branch = "slash-worktree-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Worktree Project")
        model.selectProject(projectID)

        model.setDraft("/worktree create \(worktreeName) --branch \(branch)")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.selectedProject?.path, worktree.path)
        XCTAssertEqual(model.selectedThread?.title, "Worktree: \(branch)")
        XCTAssertEqual(model.root.topBar.projectName, worktreeName)

        model.selectProject(projectID)
        model.setDraft("/worktree open \(worktreeName)")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.selectedProject?.path, worktree.path)
        XCTAssertEqual(model.selectedThread?.title, "Worktree: \(worktreeName)")
        let openCard = try XCTUnwrap(worktreeCard(in: model, title: ToolDefinition.gitWorktreeOpen.name))
        XCTAssertNotEqual(openCard.threadID, model.selectedThread?.id)
        XCTAssertEqual(openCard.card.status, .done)
        XCTAssertTrue(openCard.card.inputJSON?.contains(worktreeName) == true)

        model.selectProject(projectID)
        model.setDraft("/worktree remove \(worktreeName) --force")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitWorktreeRemove.name)
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

    func testSlashSubagentsRunsSchedulerAndRecordsActivityProgress() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/subagents validate release | Explorer: inspect code | Verifier: run focused tests")
        await model.submitComposer(workspaceRoot: root)

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.title, "Subagents")
        XCTAssertEqual(thread.messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(thread.messages.last?.content.contains("Subagents completed 2 workers") == true)
        let latestUpdate = try XCTUnwrap(SubagentProgressToolExecutor.latestUpdate(in: thread))
        XCTAssertEqual(latestUpdate.objective, "validate release")
        XCTAssertEqual(latestUpdate.subagents.map(\.name), ["Explorer", "Verifier"])
        XCTAssertEqual(latestUpdate.subagents.map(\.status), [.completed, .completed])
        XCTAssertEqual(model.surface().activity.subagents.map(\.title), ["Explorer", "Verifier"])
        XCTAssertEqual(model.surface().activity.subagents.map(\.statusLabel), ["Done", "Done"])
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.subagentsUpdate.name)
    }

    func testSlashSubagentsRunsDelegatedChildrenAndRecordsActivityPath() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        model.subagentScheduler = WorkspaceSubagentScheduler { job in
            job.depth == 0
                ? "Planned the split. [[DELEGATE: Compile | compile the app]]"
                : "did \(job.role)"
        }

        model.setDraft("/subagents ship app | Planner: plan the work")
        await model.submitComposer(workspaceRoot: root)

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertTrue(thread.messages.last?.content.contains("Subagents completed 2 workers") == true)

        let latestUpdate = try XCTUnwrap(SubagentProgressToolExecutor.latestUpdate(in: thread))
        XCTAssertEqual(latestUpdate.objective, "ship app")
        XCTAssertEqual(latestUpdate.subagents.map(\.name), ["Planner", "Planner/Compile"])
        XCTAssertEqual(latestUpdate.subagents.map(\.groupPath), [[], ["Planner"]])
        XCTAssertEqual(latestUpdate.subagents.map(\.status), [.completed, .completed])
        XCTAssertEqual(latestUpdate.subagents.last?.summary, "did compile the app")

        let activity = model.surface().activity.subagents
        XCTAssertEqual(activity.map(\.title), ["Planner", "Compile"])
        XCTAssertEqual(activity.map(\.statusLabel), ["Done", "Done"])
        XCTAssertTrue(activity.last?.detail.contains("Path: Planner / Compile") == true)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.subagentsUpdate.name)
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

    func testSlashModelPrometheusAliasWritesBrandedTranscript() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/model /prometheus")
        await model.submitComposer(workspaceRoot: try makeQuillCodeTestDirectory())

        XCTAssertEqual(model.root.config.defaultModel, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(model.selectedThread?.model, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Model set to Prometheus 1.0 (/prometheus).")
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
        XCTAssertTrue(message.contains("Model: Nike 1.0 (trustedrouter/fast)"))
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
