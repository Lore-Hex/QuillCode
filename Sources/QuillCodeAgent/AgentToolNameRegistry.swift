import Foundation
import QuillCodeCore
import QuillCodeTools

/// The set of built-in tool names the action parser will accept as a `type` discriminant, so a weak
/// model that emits `{"type":"host.file.list","arguments":{...}}` (tool name in `type`) is recovered
/// instead of failing the whole run.
///
/// It is deliberately a CLOSED STATIC set — every tool the runtime always advertises (shell/file/git
/// via `ToolRouter`, which already folds in LSP, plus the core workflow tools: plan, handoff,
/// subagents, browser, memory, review) — and NEVER dynamic MCP or per-run tools. That keeps membership
/// stable and means the coercion can't be tricked into treating an arbitrary string as a tool. An
/// unknown `type` still fails exactly as before.
///
/// Computer-use tools are intentionally omitted: they are only advertised when Computer Use is granted,
/// so they are not part of the always-present static set. If a weak model fumbles their envelope the
/// resolver's corrective re-prompt still applies — this coercion just doesn't shortcut it.
enum AgentToolNameRegistry {
    /// The always-advertised core workflow tools that live in `QuillCodeCore` rather than `ToolRouter`.
    /// Listed explicitly (not derived from a run-context builder) so this stays a pure static set.
    private static let coreWorkflowDefinitions: [ToolDefinition] = [
        .planUpdate,
        .handoffUpdate,
        .subagentsRun,
        .subagentsUpdate,
        .browserInspect,
        .browserOpen,
        .browserClick,
        .browserType,
        .browserScript,
        .memoryRemember,
        .codeReviewSubmit,
    ]

    static let knownToolNames: Set<String> = {
        var names = Set(ToolRouter.definitions.map(\.name)) // includes LSP definitions
        names.formUnion(coreWorkflowDefinitions.map(\.name))
        return names
    }()

    static func isKnownToolName(_ name: String) -> Bool {
        knownToolNames.contains(name)
    }
}
