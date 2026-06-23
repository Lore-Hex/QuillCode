import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceMCPToolCatalog: Sendable, Hashable {
    var manifests: [ProjectExtensionManifest]
    var extensions: ExtensionsState
    var runningServerIDs: Set<String>

    init(
        manifests: [ProjectExtensionManifest],
        extensions: ExtensionsState,
        runningServerIDs: Set<String>
    ) {
        self.manifests = manifests
        self.extensions = extensions
        self.runningServerIDs = runningServerIDs
    }

    func toolDefinitions() -> [ToolDefinition] {
        [
            mcpCallDefinition(),
            mcpReadResourceDefinition(),
            mcpGetPromptDefinition()
        ].compactMap { $0 }
    }

    func readyToolDescriptions() -> [String] {
        readyMCPManifests().compactMap { manifest in
            guard let summary = extensions.mcpServerProbeSummaries[manifest.id],
                  !summary.toolDescriptors.isEmpty
            else { return nil }
            let tools = summary.toolDescriptors.map(toolDescription)
            return "- \(manifest.id) (\(manifest.name)): \(tools.joined(separator: ", "))"
        }
    }

    func readyResourceDescriptions() -> [String] {
        readyMCPManifests().compactMap { manifest in
            guard let summary = extensions.mcpServerProbeSummaries[manifest.id],
                  !summary.resourceNames.isEmpty
            else { return nil }
            let resources = zip(summary.resourceNames, summary.resourceURIs).map { name, uri in
                name == uri ? uri : "\(name) [\(uri)]"
            }
            let fallbackResources = Array(summary.resourceNames.dropFirst(resources.count))
            return "- \(manifest.id) (\(manifest.name)): \((resources + fallbackResources).joined(separator: ", "))"
        }
    }

    func readyPromptDescriptions() -> [String] {
        readyMCPManifests().compactMap { manifest in
            let prompts = extensions.mcpServerProbeSummaries[manifest.id]?.promptNames ?? []
            guard !prompts.isEmpty else { return nil }
            return "- \(manifest.id) (\(manifest.name)): \(prompts.joined(separator: ", "))"
        }
    }

    private func mcpCallDefinition() -> ToolDefinition? {
        let readyTools = readyToolDescriptions()
        guard !readyTools.isEmpty else { return nil }

        var definition = ToolDefinition.mcpCall
        definition.description = """
        Call a tool on a verified project-local MCP stdio server. Use only these Ready MCP tools:
        \(readyTools.joined(separator: "\n"))
        """
        return definition
    }

    private func mcpReadResourceDefinition() -> ToolDefinition? {
        let readyResources = readyResourceDescriptions()
        guard !readyResources.isEmpty else { return nil }

        var definition = ToolDefinition.mcpReadResource
        definition.description = """
        Read a resource from a verified project-local MCP stdio server. Use only these Ready MCP resources:
        \(readyResources.joined(separator: "\n"))
        """
        return definition
    }

    private func mcpGetPromptDefinition() -> ToolDefinition? {
        let readyPrompts = readyPromptDescriptions()
        guard !readyPrompts.isEmpty else { return nil }

        var definition = ToolDefinition.mcpGetPrompt
        definition.description = """
        Get a prompt from a verified project-local MCP stdio server. Use only these Ready MCP prompts:
        \(readyPrompts.joined(separator: "\n"))
        """
        return definition
    }

    private func readyMCPManifests() -> [ProjectExtensionManifest] {
        manifests.filter { manifest in
            manifest.kind == .mcpServer
                && extensions.mcpServerStatuses[manifest.id] == .ready
                && runningServerIDs.contains(manifest.id)
        }
    }

    private func toolDescription(for descriptor: MCPToolDescriptor) -> String {
        var details: [String] = []
        if !descriptor.schemaSummary.isEmpty {
            details.append(descriptor.schemaSummary)
        }
        if !descriptor.description.isEmpty {
            details.append(descriptor.description)
        }
        return details.isEmpty
            ? descriptor.name
            : "\(descriptor.name) [\(details.joined(separator: "; "))]"
    }
}
