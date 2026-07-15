import Foundation
import QuillCodeCore

public extension MCPToolCallResult {
    /// Converts an exact MCP wire result into the text-oriented result consumed by agent turns.
    /// Direct app-server MCP calls continue to return the original structured payload unchanged.
    func agentToolResult() -> ToolResult {
        MCPStdioResultMapper.toolResult(from: self)
    }
}
