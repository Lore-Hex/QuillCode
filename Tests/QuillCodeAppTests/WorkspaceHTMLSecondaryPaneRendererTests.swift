import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceHTMLSecondaryPaneRendererTests: XCTestCase {
    func testHTMLRendererIncludesVisibleExtensionsPane() throws {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
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
            extensions: ExtensionsState(
                isVisible: true,
                mcpServerStatuses: ["mcp_server:filesystem": .ready],
                mcpServerProbeSummaries: [
                    "mcp_server:filesystem": MCPServerProbeSummary(
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
                        ]
                    )
                ]
            )
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="extensions-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-item""#))
        XCTAssertTrue(html.contains("Filesystem MCP"))
        XCTAssertTrue(html.contains(#"data-testid="extension-transport""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-stop""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-mcp-tool-schema">required: path:string · Read a file"#))
        XCTAssertTrue(html.contains(".quillcode/mcp/filesystem.json"))
    }

    func testHTMLRendererIncludesVisibleMemoriesPane() throws {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            memories: [
                MemoryNote(
                    id: "project:.quillcode/memories/project.md",
                    scope: .project,
                    title: "Project",
                    content: "Use SwiftUI surfaces for visible state.",
                    relativePath: ".quillcode/memories/project.md",
                    byteCount: 38
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            memories: MemoriesState(isVisible: true)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="memories-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="memory-item""#))
        XCTAssertTrue(html.contains("Project"))
        XCTAssertTrue(html.contains(".quillcode/memories/project.md"))
    }
}
