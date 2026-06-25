import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class ProjectExtensionManifestSurfaceTests: XCTestCase {
    func testMCPManifestMapsProbeMetadataAndActions() {
        let manifest = ProjectExtensionManifest(
            id: "mcp_server:filesystem",
            kind: .mcpServer,
            name: "Filesystem MCP",
            summary: "Expose workspace files.",
            version: "1.2.3",
            sourceURL: "https://example.com/mcp",
            relativePath: ".quillcode/mcp/filesystem.json",
            transport: .stdio,
            launchExecutable: "quill-mcp",
            launchCommand: "quill-mcp --root .",
            installCommand: "quill-mcp install",
            updateCommand: "quill-mcp update"
        )
        let probe = MCPServerProbeSummary(
            protocolVersion: "2024-11-05",
            serverName: "Fixture MCP",
            serverVersion: "1.0.0",
            toolDescriptors: [
                MCPToolDescriptor(
                    name: "read_file",
                    description: "Read a file",
                    requiredArguments: ["path"],
                    schemaSummary: "required: path:string"
                )
            ],
            resourceNames: ["README"],
            promptNames: ["summarize_project"]
        )

        let surface = ProjectExtensionManifestSurface(
            manifest: manifest,
            mcpServerStatus: .ready,
            probeSummary: probe
        )

        XCTAssertEqual(surface.id, "mcp_server:filesystem")
        XCTAssertEqual(surface.kindLabel, "MCP")
        XCTAssertEqual(surface.versionLabel, "v1.2.3")
        XCTAssertEqual(surface.sourceURL, "https://example.com/mcp")
        XCTAssertEqual(surface.statusLabel, "Ready")
        XCTAssertEqual(surface.transportLabel, "STDIO")
        XCTAssertEqual(surface.serverLabel, "Fixture MCP 1.0.0")
        XCTAssertEqual(surface.protocolLabel, "MCP 2024-11-05")
        XCTAssertEqual(surface.toolCountLabel, "1 tool")
        XCTAssertEqual(surface.toolDescriptors.map { $0.schemaSummary }, ["required: path:string"])
        XCTAssertEqual(surface.resourceNames, ["README"])
        XCTAssertEqual(surface.promptNames, ["summarize_project"])
        XCTAssertFalse(surface.canStart)
        XCTAssertTrue(surface.canStop)
        XCTAssertTrue(surface.canInstall)
        XCTAssertTrue(surface.canUpdate)
        XCTAssertNil(surface.startCommandID)
        XCTAssertEqual(surface.stopCommandID, "mcp-stop:mcp_server:filesystem")
        XCTAssertEqual(surface.installCommandID, "extension-install:mcp_server:filesystem")
        XCTAssertEqual(surface.updateCommandID, "extension-update:mcp_server:filesystem")
    }

    func testDisabledAndMissingCommandManifestsDoNotExposeStartActions() {
        let disabled = ProjectExtensionManifest(
            id: "plugin:disabled",
            kind: .plugin,
            name: "Disabled plugin",
            summary: "Disabled.",
            relativePath: ".quillcode/plugins/disabled.json",
            isEnabled: false
        )
        let missingCommand = ProjectExtensionManifest(
            id: "mcp_server:missing",
            kind: .mcpServer,
            name: "Missing MCP",
            summary: "No command.",
            relativePath: ".quillcode/mcp/missing.json"
        )

        let disabledSurface = ProjectExtensionManifestSurface(manifest: disabled)
        let missingCommandSurface = ProjectExtensionManifestSurface(manifest: missingCommand)

        XCTAssertEqual(disabledSurface.statusLabel, "Disabled")
        XCTAssertFalse(disabledSurface.canStart)
        XCTAssertNil(disabledSurface.startCommandID)
        XCTAssertEqual(missingCommandSurface.statusLabel, "Missing command")
        XCTAssertFalse(missingCommandSurface.canStart)
        XCTAssertNil(missingCommandSurface.startCommandID)
    }

    func testDecodesOlderPayloadWithoutMCPResourcesPromptsOrUpdateMetadata() throws {
        let data = """
        {
          "id": "mcp_server:filesystem",
          "kind": "mcp_server",
          "kindLabel": "MCP",
          "name": "Filesystem MCP",
          "summary": "Workspace MCP server.",
          "relativePath": ".quillcode/mcp/filesystem.json",
          "statusLabel": "Ready",
          "transportLabel": "STDIO",
          "launchCommand": "quill-mcp --root .",
          "serverLabel": "Fixture MCP 1.0.0",
          "protocolLabel": "MCP 2024-11-05",
          "toolCountLabel": "2 tools",
          "toolNames": ["read_file", "write_file"],
          "probeError": null,
          "canStart": false,
          "canStop": true,
          "startCommandID": null,
          "stopCommandID": "mcp-stop:mcp_server:filesystem"
        }
        """.data(using: .utf8)!

        let surface = try JSONDecoder().decode(ProjectExtensionManifestSurface.self, from: data)

        XCTAssertEqual(surface.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(surface.toolDescriptors.map(\.name), ["read_file", "write_file"])
        XCTAssertEqual(surface.toolDescriptors.map(\.schemaSummary), ["", ""])
        XCTAssertEqual(surface.resourceNames, [])
        XCTAssertEqual(surface.promptNames, [])
        XCTAssertNil(surface.resourceCountLabel)
        XCTAssertNil(surface.promptCountLabel)
        XCTAssertNil(surface.versionLabel)
        XCTAssertNil(surface.sourceURL)
        XCTAssertFalse(surface.canInstall)
        XCTAssertNil(surface.installCommandID)
        XCTAssertFalse(surface.canUpdate)
        XCTAssertNil(surface.updateCommandID)
    }
}
