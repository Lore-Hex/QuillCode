import QuillCodeCore

private enum MCPToolDefinitionSchema {
    static let call = #"""
    {"type":"object","required":["serverID","toolName"],"properties":{"serverID":{"type":"string"},"toolName":{"type":"string"},"arguments":{"type":"object"},"argumentsJSON":{"type":"string","description":"JSON object string for tool arguments when object arguments are not convenient."}}}
    """#

    static let readResource = #"""
    {"type":"object","required":["serverID"],"properties":{"serverID":{"type":"string"},"resourceURI":{"type":"string","description":"Advertised MCP resource URI."},"uri":{"type":"string","description":"Alias for resourceURI."},"resourceName":{"type":"string","description":"Advertised resource display name when the URI is not convenient."},"name":{"type":"string","description":"Alias for resourceName."}}}
    """#

    static let getPrompt = #"""
    {"type":"object","required":["serverID","promptName"],"properties":{"serverID":{"type":"string"},"promptName":{"type":"string"},"name":{"type":"string","description":"Alias for promptName."},"arguments":{"type":"object"},"argumentsJSON":{"type":"string","description":"JSON object string for prompt arguments when object arguments are not convenient."}}}
    """#
}

public extension ToolDefinition {
    static let mcpCall = ToolDefinition(
        name: "host.mcp.call",
        description: "Call a tool on a verified project-local MCP stdio server. "
            + "Use only server IDs and tool names listed in the description supplied by QuillCode.",
        parametersJSON: MCPToolDefinitionSchema.call,
        host: .mcp,
        risk: .append
    )

    static let mcpReadResource = ToolDefinition(
        name: "host.mcp.resource.read",
        description: "Read an advertised resource from a verified project-local MCP stdio server. "
            + "Use only server IDs and resource names or URIs listed in the description supplied by QuillCode.",
        parametersJSON: MCPToolDefinitionSchema.readResource,
        host: .mcp,
        risk: .read
    )

    static let mcpGetPrompt = ToolDefinition(
        name: "host.mcp.prompt.get",
        description: "Get an advertised prompt from a verified project-local MCP stdio server. "
            + "Use only server IDs and prompt names listed in the description supplied by QuillCode.",
        parametersJSON: MCPToolDefinitionSchema.getPrompt,
        host: .mcp,
        risk: .read
    )
}
