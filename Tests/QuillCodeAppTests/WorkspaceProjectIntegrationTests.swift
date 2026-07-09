import XCTest
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceProjectIntegrationTests: XCTestCase {
    func testModelPersistsProjectRegistryChanges() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let model = QuillCodeWorkspaceModel(projectStore: projectStore)

        _ = model.addProject(path: root, name: "QuillCode")

        XCTAssertEqual(try projectStore.load().map(\.name), ["QuillCode"])
    }

    func testSelectingProjectControlsNextChatAndWorkspaceRoot() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let projectID = model.addProject(path: root, name: "QuillCode")
        model.selectProject(projectID)
        let threadID = model.newChat()

        XCTAssertEqual(model.root.selectedProjectID, projectID)
        XCTAssertEqual(model.root.selectedThreadID, threadID)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
        XCTAssertEqual(model.selectedProject?.name, "QuillCode")
        XCTAssertEqual(model.activeWorkspaceRoot?.path, root.standardizedFileURL.path)
        XCTAssertEqual(model.root.topBar.projectName, "QuillCode")
    }

    func testProjectLifecycleActionsRenameRefreshNewChatAndRemove() throws {
        let root = try makeTempDirectory()
        try "Use focused tests.".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Original")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertTrue(model.renameProject(projectID, to: "Renamed Project"))
        XCTAssertEqual(model.selectedProject?.name, "Renamed Project")
        XCTAssertEqual(model.root.topBar.projectName, "Renamed Project")

        XCTAssertTrue(model.refreshProjectContext(projectID))
        XCTAssertEqual(model.selectedThread?.instructions.map(\.title), ["Project AGENTS.md"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Refreshed project context")

        XCTAssertTrue(model.runWorkspaceCommand("project-new-chat", workspaceRoot: root))
        XCTAssertNotEqual(model.root.selectedThreadID, threadID)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)

        XCTAssertTrue(model.runWorkspaceCommand("project-remove", workspaceRoot: root))
        XCTAssertTrue(model.root.projects.isEmpty)
        XCTAssertNil(model.root.selectedProjectID)
        XCTAssertNil(model.selectedThread?.projectID)
        XCTAssertNil(model.activeWorkspaceRoot)
    }

    func testProjectReorderCommandsMoveSelectedProject() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        let alpha = model.addProject(path: root.appendingPathComponent("Alpha"), name: "Alpha")
        model.addProject(path: root.appendingPathComponent("Beta"), name: "Beta")
        let gamma = model.addProject(path: root.appendingPathComponent("Gamma"), name: "Gamma")

        XCTAssertEqual(projectNames(in: model), ["Gamma", "Beta", "Alpha"])

        model.selectProject(gamma)
        XCTAssertTrue(model.runWorkspaceCommand("project-move-down", workspaceRoot: root))
        XCTAssertEqual(projectNames(in: model), ["Beta", "Gamma", "Alpha"])

        XCTAssertTrue(model.runWorkspaceCommand("project-move-up", workspaceRoot: root))
        XCTAssertEqual(projectNames(in: model), ["Gamma", "Beta", "Alpha"])

        model.selectProject(alpha)
        XCTAssertTrue(model.runWorkspaceCommand("project-move-to-top", workspaceRoot: root))
        XCTAssertEqual(projectNames(in: model), ["Alpha", "Gamma", "Beta"])
        XCTAssertTrue(model.runWorkspaceCommand("project-move-to-bottom", workspaceRoot: root))
        XCTAssertEqual(projectNames(in: model), ["Gamma", "Beta", "Alpha"])
        XCTAssertFalse(model.runWorkspaceCommand("project-move-to-bottom", workspaceRoot: root))
        XCTAssertFalse(model.runWorkspaceCommand("project-move-down", workspaceRoot: root))

        XCTAssertTrue(model.moveProject(alpha, before: gamma))
        XCTAssertEqual(projectNames(in: model), ["Alpha", "Gamma", "Beta"])
        XCTAssertFalse(model.moveProject(alpha, before: gamma))
        XCTAssertEqual(model.root.selectedProjectID, alpha)
    }

    func testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun() async throws {
        let root = try makeQuillCodeTestDirectory()
        try "Prefer Swift tests before final answers.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let quillcodeDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillcodeDirectory, withIntermediateDirectories: true)
        try "Use small focused commits.\n".write(
            to: quillcodeDirectory.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Rules Project")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertEqual(model.root.projects.first?.instructions.map(\.path), [
            "AGENTS.md",
            ".quillcode/rules.md"
        ])
        XCTAssertEqual(model.root.threads.first { $0.id == threadID }?.instructions.count, 2)
        XCTAssertEqual(model.surface().topBar.instructionLabel, "2 instruction files loaded")

        try "Prefer targeted unit tests.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertTrue(model.selectedThread?.instructions.first?.content.contains("targeted unit tests") == true)
    }

    private func projectNames(in model: QuillCodeWorkspaceModel) -> [String] {
        model.surface().projects.items.map(\.name)
    }

    func testProjectMetadataRefreshPersistsResolvedInstructionDiagnostics() throws {
        let root = try makeQuillCodeTestDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode-store"))
        try paths.ensure()
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let featureDirectory = root.appendingPathComponent("Sources/Feature")
        try FileManager.default.createDirectory(at: featureDirectory, withIntermediateDirectories: true)
        try "Always run tests before finishing.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Do not run tests for feature changes.\n".write(
            to: featureDirectory.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let model = QuillCodeWorkspaceModel(projectStore: projectStore)
        let projectID = model.addProject(path: root, name: "Rules Project")
        let diagnosticID = try XCTUnwrap(
            ProjectInstructionDiagnosticsBuilder
                .diagnostics(for: model.root.projects[0].instructions)
                .first { $0.statusLabel == "conflict" }?
                .id
        )

        try "Always run focused tests before finishing.\n".write(
            to: featureDirectory.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        model.refreshProjectMetadata(projectID)

        let loaded = try XCTUnwrap(projectStore.load().first)
        XCTAssertEqual(loaded.resolvedInstructionDiagnosticIDs, [diagnosticID])
        XCTAssertEqual(loaded.dismissedInstructionDiagnosticIDs, [])
    }
}
