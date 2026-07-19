import Foundation
import QuillCodeTools

/// The set of built-in tool names the action parser will accept as a `type` discriminant, so a weak
/// model that emits `{"type":"host.file.list","arguments":{...}}` (tool name in `type`) is recovered
/// instead of failing the whole run. Deliberately the STATIC built-in registry only (shell/file/git/
/// plan/LSP + the always-present workflow tools) — never dynamic MCP or per-run tools — so membership
/// is a stable, closed set and the coercion can never be tricked into treating an arbitrary string as
/// a tool. An unknown `type` still fails, exactly as before.
enum AgentToolNameRegistry {
    static let knownToolNames: Set<String> = {
        var names = Set(ToolRouter.definitions.map(\.name))
        names.formUnion(LSPToolCallDispatcher.definitions.map(\.name))
        return names
    }()

    static func isKnownToolName(_ name: String) -> Bool {
        knownToolNames.contains(name)
    }
}
