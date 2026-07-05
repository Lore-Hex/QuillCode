import XCTest
import QuillCodeCore
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
        XCTAssertEqual(extensions.skillCount, 1)
        XCTAssertEqual(extensions.mcpServerCount, 0)
        XCTAssertEqual(extensions.items.first?.name, "GitHub")
        XCTAssertEqual(extensions.items.first?.relativePath, ".quillcode/plugins/github.json")
        XCTAssertEqual(extensions.items.last?.name, "BurstyRouter")
        XCTAssertEqual(extensions.items.last?.statusLabel, "Available")
    }

    func testSurfaceIncludesProjectExtensionSummaryAndCommand() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "plugin:github",
                    kind: .plugin,
                    name: "GitHub",
                    summary: "PR workflow helpers.",
                    version: "1.2.0",
                    sourceURL: "https://github.com/Lore-Hex/quillcode-github",
                    relativePath: ".quillcode/plugins/github.json",
                    installCommand: "git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github",
                    installTimeoutSeconds: 600,
                    updateCommand: "git -C .quillcode/plugins/github pull --ff-only",
                    updateTimeoutSeconds: 300
                ),
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    summary: "Workspace MCP server.",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    transport: .stdio,
                    launchExecutable: "quill-mcp",
                    launchCommand: "quill-mcp --root .",
                    launchArguments: ["--root", "."]
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(isVisible: true)
        )

        let surface = model.surface()

        XCTAssertEqual(surface.extensions.subtitle, "1 plugin · 0 skills · 1 MCP server")
        XCTAssertEqual(surface.extensions.items.map(\.kindLabel), ["Plugin", "MCP"])
        XCTAssertEqual(surface.extensions.items.map(\.statusLabel), ["Discovered", "Stopped"])
        XCTAssertEqual(surface.extensions.items.first?.versionLabel, "v1.2.0")
        XCTAssertEqual(surface.extensions.items.first?.sourceURL, "https://github.com/Lore-Hex/quillcode-github")
        XCTAssertEqual(surface.extensions.items.first?.installCommandID, "extension-install:plugin:github")
        XCTAssertEqual(surface.extensions.items.first?.updateCommandID, "extension-update:plugin:github")
        XCTAssertEqual(surface.commands.first { $0.id == "extension-install:plugin:github" }?.title, "Install GitHub")
        XCTAssertEqual(surface.commands.first { $0.id == "extension-install:plugin:github" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "extension-update:plugin:github" }?.title, "Update GitHub")
        XCTAssertEqual(surface.commands.first { $0.id == "extension-update:plugin:github" }?.isEnabled, true)
        XCTAssertEqual(surface.extensions.items.last?.transportLabel, "STDIO")
        XCTAssertEqual(surface.extensions.items.last?.launchCommand, "quill-mcp --root .")
        XCTAssertEqual(surface.extensions.items.last?.startCommandID, "mcp-start:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-start:mcp_server:filesystem" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-stop:mcp_server:filesystem" }?.isEnabled, false)
        XCTAssertEqual(
            surface.commands.first { $0.id == "toggle-extensions" }?.category,
            WorkspaceCommandPalette.extensionsCategory
        )
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-extensions" }?.isEnabled, true)
    }

    func testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata() throws {
        let setup = try makeProjectWithPluginManifest(
            #"""
            {
              "id": "github",
              "name": "GitHub",
              "description": "PR workflow helpers.",
              "version": "1.0.0",
              "updateCommand": "printf updated > .quillcode/plugins/update.marker",
              "updateTimeoutSeconds": 30
            }
            """#
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("extension-update:plugin:github", workspaceRoot: setup.root))

        let marker = try String(
            contentsOf: setup.pluginDirectory.appendingPathComponent("update.marker"),
            encoding: .utf8
        )
        XCTAssertEqual(marker, "updated")
        XCTAssertEqual(setup.model.surface().extensions.items.first?.updateCommandID, "extension-update:plugin:github")
        XCTAssertTrue(setup.model.selectedThread?.events.contains { $0.summary == "Updated extension GitHub" } == true)
    }

    func testProjectExtensionInstallCommandRunsAndRefreshesProjectMetadata() throws {
        let setup = try makeProjectWithPluginManifest(
            #"""
            {
              "id": "github",
              "name": "GitHub",
              "description": "PR workflow helpers.",
              "version": "1.0.0",
              "installCommand": "printf installed > .quillcode/plugins/install.marker",
              "installTimeoutSeconds": 30
            }
            """#
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("extension-install:plugin:github", workspaceRoot: setup.root))

        let marker = try String(
            contentsOf: setup.pluginDirectory.appendingPathComponent("install.marker"),
            encoding: .utf8
        )
        XCTAssertEqual(marker, "installed")
        XCTAssertEqual(
            setup.model.surface().extensions.items.first?.installCommandID,
            "extension-install:plugin:github"
        )
        XCTAssertTrue(
            setup.model.selectedThread?.events.contains { $0.summary == "Installed extension GitHub" } == true
        )
    }

    func testProjectMarketplaceInstallRefreshesToInstalledManifest() throws {
        let root = try makeQuillCodeTestDirectory()
        let marketplaceDirectory = root.appendingPathComponent(".quillcode/marketplace")
        try FileManager.default.createDirectory(at: marketplaceDirectory, withIntermediateDirectories: true)
        try #"""
        {
          "id": "github",
          "kind": "plugin",
          "name": "GitHub",
          "description": "PR workflow helpers.",
          "version": "1.2.0",
          "installCommand": "mkdir -p .quillcode/plugins && printf '%s' '{\"id\":\"github\",\"name\":\"GitHub\",\"description\":\"Installed PR workflow helpers.\"}' > .quillcode/plugins/github.json",
          "installTimeoutSeconds": 30
        }
        """#.write(
            to: marketplaceDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Marketplace Project")
        model.selectProject(projectID)

        let available = model.surface().extensions.items.first
        XCTAssertEqual(available?.id, "plugin:github")
        XCTAssertEqual(available?.statusLabel, "Available")
        XCTAssertEqual(available?.relativePath, ".quillcode/marketplace/github.json")
        XCTAssertEqual(
            model.surface().commands.first { $0.id == "extension-install:plugin:github" }?.isEnabled,
            true
        )

        XCTAssertTrue(model.runWorkspaceCommand("extension-install:plugin:github", workspaceRoot: root))

        let installed = model.surface().extensions.items.first
        XCTAssertEqual(installed?.id, "plugin:github")
        XCTAssertEqual(installed?.statusLabel, "Discovered")
        XCTAssertEqual(installed?.relativePath, ".quillcode/plugins/github.json")
        XCTAssertEqual(installed?.summary, "Installed PR workflow helpers.")
        XCTAssertTrue(
            model.selectedThread?.events.contains { $0.summary == "Installed extension GitHub" } == true
        )
    }

    func testProjectExtensionUpdateFailureKeepsManifestAndRecordsFailureNotice() throws {
        let setup = try makeProjectWithPluginManifest(
            #"""
            {
              "id": "github",
              "name": "GitHub",
              "description": "PR workflow helpers.",
              "version": "1.0.0",
              "updateCommand": "sh -c 'exit 7'",
              "updateTimeoutSeconds": 30
            }
            """#
        )

        XCTAssertFalse(setup.model.runWorkspaceCommand("extension-update:plugin:github", workspaceRoot: setup.root))

        XCTAssertEqual(setup.model.surface().extensions.items.first?.updateCommandID, "extension-update:plugin:github")
        XCTAssertTrue(
            setup.model.selectedThread?.events.contains { $0.summary == "Extension update failed for GitHub" } == true
        )
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
