import XCTest
@testable import QuillCodeApp

@MainActor
final class WorkspaceProjectExtensionIntegrationTests: XCTestCase {
    func testProjectExtensionManifestsLoadIntoProjectSurface() throws {
        let setup = try makeProjectWithPluginManifest(
            #"{"id":"github","name":"GitHub","description":"PR workflow helpers."}"#
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("toggle-extensions", workspaceRoot: setup.root))

        let extensions = setup.model.surface().extensions
        XCTAssertTrue(extensions.isVisible)
        XCTAssertEqual(extensions.pluginCount, 1)
        XCTAssertEqual(extensions.skillCount, 0)
        XCTAssertEqual(extensions.mcpServerCount, 0)
        XCTAssertEqual(extensions.items.first?.name, "GitHub")
        XCTAssertEqual(extensions.items.first?.relativePath, ".quillcode/plugins/github.json")
    }

    func testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata() throws {
        let setup = try makeProjectWithPluginManifest(
            #"{"id":"github","name":"GitHub","description":"PR workflow helpers.","version":"1.0.0","updateCommand":"printf updated > .quillcode/plugins/update.marker","updateTimeoutSeconds":30}"#
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("extension-update:plugin:github", workspaceRoot: setup.root))

        let marker = try String(contentsOf: setup.pluginDirectory.appendingPathComponent("update.marker"), encoding: .utf8)
        XCTAssertEqual(marker, "updated")
        XCTAssertEqual(setup.model.surface().extensions.items.first?.updateCommandID, "extension-update:plugin:github")
        XCTAssertTrue(setup.model.selectedThread?.events.contains { $0.summary == "Updated extension GitHub" } == true)
    }

    func testProjectExtensionUpdateFailureKeepsManifestAndRecordsFailureNotice() throws {
        let setup = try makeProjectWithPluginManifest(
            #"{"id":"github","name":"GitHub","description":"PR workflow helpers.","version":"1.0.0","updateCommand":"sh -c 'exit 7'","updateTimeoutSeconds":30}"#
        )

        XCTAssertFalse(setup.model.runWorkspaceCommand("extension-update:plugin:github", workspaceRoot: setup.root))

        XCTAssertEqual(setup.model.surface().extensions.items.first?.updateCommandID, "extension-update:plugin:github")
        XCTAssertTrue(setup.model.selectedThread?.events.contains { $0.summary == "Extension update failed for GitHub" } == true)
    }

    private func makeProjectWithPluginManifest(
        _ manifestJSON: String
    ) throws -> (root: URL, pluginDirectory: URL, model: QuillCodeWorkspaceModel) {
        let root = try makeQuillCodeTestDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try manifestJSON.write(
            to: pluginDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Extension Project")
        model.selectProject(projectID)
        return (root, pluginDirectory, model)
    }
}
