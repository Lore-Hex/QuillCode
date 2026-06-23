import XCTest
@testable import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

final class WorkspaceMCPToolCatalogTests: XCTestCase {
    func testToolDefinitionsExposeOnlyReadyRunningAdvertisedCapabilities() {
        let catalog = WorkspaceMCPToolCatalog(
            manifests: [
                manifest(id: "fs", name: "Filesystem"),
                manifest(id: "stopped", name: "Stopped"),
                manifest(id: "plugin", kind: .plugin, name: "Plugin")
            ],
            extensions: ExtensionsState(
                mcpServerStatuses: [
                    "fs": .ready,
                    "stopped": .ready,
                    "plugin": .ready
                ],
                mcpServerProbeSummaries: [
                    "fs": MCPServerProbeSummary(
                        toolDescriptors: [
                            MCPToolDescriptor(
                                name: "read_file",
                                description: "Read a file",
                                requiredArguments: ["path"],
                                schemaSummary: "path: string"
                            )
                        ],
                        resourceNames: ["Guide", "Readme"],
                        resourceURIs: ["file:///guide.md"],
                        promptNames: ["summarize"]
                    ),
                    "stopped": MCPServerProbeSummary(toolNames: ["ignored"]),
                    "plugin": MCPServerProbeSummary(toolNames: ["also_ignored"])
                ]
            ),
            runningServerIDs: ["fs"]
        )

        let definitions = catalog.toolDefinitions()

        XCTAssertEqual(definitions.map(\.name), [
            ToolDefinition.mcpCall.name,
            ToolDefinition.mcpReadResource.name,
            ToolDefinition.mcpGetPrompt.name
        ])
        XCTAssertTrue(definitions[0].description.contains("- fs (Filesystem): read_file [path: string; Read a file]"))
        XCTAssertTrue(definitions[1].description.contains("- fs (Filesystem): Guide [file:///guide.md], Readme"))
        XCTAssertTrue(definitions[2].description.contains("- fs (Filesystem): summarize"))
        XCTAssertFalse(definitions.map(\.description).joined(separator: "\n").contains("stopped"))
        XCTAssertFalse(definitions.map(\.description).joined(separator: "\n").contains("plugin"))
    }

    func testToolDefinitionsOmitUnavailableCapabilityGroups() {
        let catalog = WorkspaceMCPToolCatalog(
            manifests: [manifest(id: "resources", name: "Resources")],
            extensions: ExtensionsState(
                mcpServerStatuses: ["resources": .ready],
                mcpServerProbeSummaries: [
                    "resources": MCPServerProbeSummary(
                        resourceNames: ["Guide"],
                        resourceURIs: ["file:///guide.md"]
                    )
                ]
            ),
            runningServerIDs: ["resources"]
        )

        XCTAssertEqual(catalog.toolDefinitions().map(\.name), [ToolDefinition.mcpReadResource.name])
        XCTAssertEqual(catalog.readyToolDescriptions(), [])
        XCTAssertEqual(catalog.readyPromptDescriptions(), [])
    }

    func testCatalogRequiresReadyStatusAndRunningProcess() {
        let catalog = WorkspaceMCPToolCatalog(
            manifests: [
                manifest(id: "probing", name: "Probing"),
                manifest(id: "not-running", name: "Not Running")
            ],
            extensions: ExtensionsState(
                mcpServerStatuses: [
                    "probing": .probing,
                    "not-running": .ready
                ],
                mcpServerProbeSummaries: [
                    "probing": MCPServerProbeSummary(toolNames: ["probe"]),
                    "not-running": MCPServerProbeSummary(toolNames: ["offline"])
                ]
            ),
            runningServerIDs: ["probing"]
        )

        XCTAssertEqual(catalog.toolDefinitions(), [])
        XCTAssertEqual(catalog.readyToolDescriptions(), [])
    }

    func testRuntimeDelegatesDynamicToolDefinitionsToCatalog() {
        let definitions = WorkspaceMCPRuntime.toolDefinitions(
            manifests: [manifest(id: "fs", name: "Filesystem")],
            extensions: ExtensionsState(
                mcpServerStatuses: ["fs": .ready],
                mcpServerProbeSummaries: ["fs": MCPServerProbeSummary(toolNames: ["read_file"])]
            ),
            runningServerIDs: ["fs"]
        )

        XCTAssertEqual(definitions.map(\.name), [ToolDefinition.mcpCall.name])
        XCTAssertTrue(definitions[0].description.contains("- fs (Filesystem): read_file"))
    }

    func testRuntimeProbeNoticeSuffixSummarizesToolsResourcesAndPrompts() {
        let result = MCPServerProbeResult(
            toolDescriptors: [
                MCPToolDescriptor(name: "one"),
                MCPToolDescriptor(name: "two"),
                MCPToolDescriptor(name: "three"),
                MCPToolDescriptor(name: "four")
            ],
            resourceNames: ["README", "Config"],
            promptNames: ["summarize"]
        )

        XCTAssertEqual(
            WorkspaceMCPRuntime.probeNoticeSuffix(for: result),
            " (4 tools: one, two, three, +1 more; 2 resources; 1 prompt)"
        )
    }

    private func manifest(
        id: String,
        kind: ProjectExtensionKind = .mcpServer,
        name: String
    ) -> ProjectExtensionManifest {
        ProjectExtensionManifest(
            id: id,
            kind: kind,
            name: name,
            relativePath: ".quillcode/mcp/\(id).json"
        )
    }
}
