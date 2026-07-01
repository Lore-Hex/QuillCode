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
        assertContainsAction(
            html,
            testID: "extension-install",
            commandID: "extension-install:plugin:github",
            title: "Install"
        )
        assertContainsAction(
            html,
            testID: "extension-update",
            commandID: "extension-update:plugin:github",
            title: "Update"
        )
        assertContainsAction(html, testID: "extension-stop", commandID: "mcp-stop:mcp_server:filesystem", title: "Stop")
        assertContainsAction(
            html,
            testID: "extension-mcp-resource-action",
            commandID: "mcp-resource:mcp_server:filesystem:0",
            title: "Read README"
        )
        assertContainsAction(
            html,
            testID: "extension-mcp-resource-action",
            commandID: "mcp-resource:mcp_server:filesystem:1",
            title: "Read Project config"
        )
        assertContainsAction(
            html,
            testID: "extension-mcp-prompt-action",
            commandID: "mcp-prompt:mcp_server:filesystem:0",
            title: "Use summarize_project"
        )
        XCTAssertFalse(html.contains(#"data-command="extension-"#))
        XCTAssertFalse(html.contains(#"data-command="mcp-"#))
        XCTAssertTrue(html.contains(".quillcode/mcp/filesystem.json"))
    }

    func testHTMLRendererIncludesAvailableMarketplaceExtensions() throws {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "plugin:github",
                    kind: .plugin,
                    name: "GitHub",
                    summary: "PR workflow helpers.",
                    relativePath: ".quillcode/marketplace/github.json",
                    installCommand: "git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github"
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(isVisible: true)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-status="Available""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-status">Available"#))
        XCTAssertTrue(html.contains(#"1 available extension"#))
        assertContainsAction(
            html,
            testID: "extension-install",
            commandID: "extension-install:plugin:github",
            title: "Install"
        )
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
        assertContainsAction(
            html,
            testID: "memory-edit",
            commandID: "memory-edit:global:memories/preferences.md",
            title: "Edit"
        )
        assertContainsAction(
            html,
            testID: "memory-edit",
            commandID: "memory-edit:project:.quillcode/memories/project.md",
            title: "Edit"
        )
        assertContainsAction(
            html,
            testID: "memory-delete",
            commandID: "memory-delete:global:memories/preferences.md",
            title: "Forget"
        )
        assertContainsAction(
            html,
            testID: "memory-delete",
            commandID: "memory-delete:project:.quillcode/memories/project.md",
            title: "Forget"
        )
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
        let conflictID = "instruction-semantic-conflict-tests-agents-md-sources-feature-agents-md"
        assertContainsAction(
            html,
            testID: "activity-source-action",
            commandID: "activity-source-open-line:1:AGENTS.md",
            title: "Open Source"
        )
        assertContainsAction(
            html,
            testID: "activity-source-action",
            commandID: "activity-source-edit-line:1:AGENTS.md",
            title: "Edit Source"
        )
        assertContainsAction(
            html,
            testID: "activity-source-action",
            commandID: "activity-instruction-apply:0:\(conflictID)",
            title: "Keep requires tests"
        )
        assertContainsAction(
            html,
            testID: "activity-source-action",
            commandID: "activity-instruction-apply:1:\(conflictID)",
            title: "Keep avoids tests"
        )
        assertContainsAction(
            html,
            testID: "activity-source-action",
            commandID: "activity-instruction-resolve:\(conflictID)",
            title: "Resolve"
        )
        assertContainsAction(
            html,
            testID: "activity-source-action",
            commandID: "activity-instruction-dismiss:\(conflictID)",
            title: "Dismiss"
        )
        assertContainsAction(
            html,
            testID: "activity-source-action",
            commandID: "activity-source-open:AGENTS.md",
            title: "Open"
        )
        assertContainsAction(
            html,
            testID: "activity-source-action",
            commandID: "activity-source-edit:AGENTS.md",
            title: "Edit"
        )
    }

    private func assertContainsAction(
        _ html: String,
        testID: String,
        commandID: String,
        title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fragment = #"data-testid="\#(testID)" data-command-id="\#(commandID)">\#(title)"#
        XCTAssertTrue(html.contains(fragment), file: file, line: line)
    }
}
