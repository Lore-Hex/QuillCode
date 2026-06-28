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
                    id: "plugin:github",
                    kind: .plugin,
                    name: "GitHub",
                    summary: "GitHub workflow helpers.",
                    version: "1.2.0",
                    sourceURL: "https://github.com/Lore-Hex/quillcode-github",
                    relativePath: ".quillcode/plugins/github.json",
                    installCommand: "git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github",
                    updateCommand: "git -C .quillcode/plugins/github pull --ff-only"
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
                        ],
                        resourceNames: ["README", "Project config"],
                        resourceURIs: ["file:///workspace/README.md", "file:///workspace/.quillcode/config.toml"],
                        promptNames: ["summarize_project"]
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
        XCTAssertTrue(html.contains(#"data-testid="extension-install" data-command-id="extension-install:plugin:github">Install"#))
        XCTAssertTrue(html.contains(#"data-testid="extension-update" data-command-id="extension-update:plugin:github">Update"#))
        XCTAssertTrue(html.contains(#"data-testid="extension-stop" data-command-id="mcp-stop:mcp_server:filesystem">Stop"#))
        XCTAssertTrue(html.contains(#"data-testid="extension-mcp-resource-action" data-command-id="mcp-resource:mcp_server:filesystem:0">Read README"#))
        XCTAssertTrue(html.contains(#"data-testid="extension-mcp-resource-action" data-command-id="mcp-resource:mcp_server:filesystem:1">Read Project config"#))
        XCTAssertTrue(html.contains(#"data-testid="extension-mcp-prompt-action" data-command-id="mcp-prompt:mcp_server:filesystem:0">Use summarize_project"#))
        XCTAssertFalse(html.contains(#"data-command="extension-"#))
        XCTAssertFalse(html.contains(#"data-command="mcp-"#))
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
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                globalMemories: [
                    MemoryNote(
                        id: "global:memories/preferences.md",
                        scope: .global,
                        title: "Preferences",
                        content: "Prefer small reviewable commits.",
                        relativePath: "memories/preferences.md",
                        byteCount: 32
                    )
                ]
            ),
            memories: MemoriesState(isVisible: true)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="memories-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="memory-item""#))
        XCTAssertTrue(html.contains(#"data-testid="memory-edit" data-command-id="memory-edit:global:memories/preferences.md">Edit"#))
        XCTAssertTrue(html.contains(#"data-testid="memory-edit" data-command-id="memory-edit:project:.quillcode/memories/project.md">Edit"#))
        XCTAssertTrue(html.contains(#"data-testid="memory-delete" data-command-id="memory-delete:global:memories/preferences.md">Forget"#))
        XCTAssertTrue(html.contains(#"data-testid="memory-delete" data-command-id="memory-delete:project:.quillcode/memories/project.md">Forget"#))
        XCTAssertTrue(html.contains("Project"))
        XCTAssertTrue(html.contains(".quillcode/memories/project.md"))
    }

    func testHTMLRendererIncludesInstructionReviewActivitySection() throws {
        let thread = ChatThread(
            title: "Inspect conflicts",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: "AGENTS.md",
                    content: "Always run tests before final answers.",
                    byteCount: 38
                ),
                ProjectInstruction(
                    path: "Sources/Feature/AGENTS.md",
                    title: "Feature AGENTS.md",
                    content: "Do not run tests for feature changes.",
                    byteCount: 37
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="activity-instruction-conflict-section""#))
        XCTAssertTrue(html.contains("Instruction Review"))
        XCTAssertTrue(html.contains(#"data-testid="activity-section-count">1 issue"#))
        XCTAssertTrue(html.contains(#"data-testid="activity-instruction-conflict" data-kind="instruction-diagnostic""#))
        XCTAssertTrue(html.contains("Tests: AGENTS.md says require; Sources/Feature/AGENTS.md says avoid"))
        XCTAssertTrue(html.contains(#"data-command-id="activity-toggle-section:instructionReview""#))
        XCTAssertTrue(html.contains(#"data-testid="activity-source-action" data-command-id="activity-instruction-resolve:instruction-semantic-conflict-tests-agents-md-sources-feature-agents-md">Resolve"#))
        XCTAssertTrue(html.contains(#"data-testid="activity-source-action" data-command-id="activity-source-open:AGENTS.md">Open"#))
        XCTAssertTrue(html.contains(#"data-testid="activity-source-action" data-command-id="activity-source-edit:AGENTS.md">Edit"#))
    }
}
