import Foundation
import QuillCodeCore

/// The normalized (action, resource) pair a permission rule table is evaluated against — and the
/// pair an "always allow/deny" answer derives its saved rule from. Building BOTH through this one
/// type guarantees a saved rule and the gate agree on spelling, so a taught rule always fires.
///
/// Resources are normalized before matching so re-spellings cannot dodge a rule:
/// - shell commands: trimmed, internal whitespace runs collapsed to single spaces
/// - workspace paths: made absolute against the workspace root, `..`/`.` resolved, and
///   symlink-resolved the same way the tool executors' `WorkspaceBoundary` gate resolves them —
///   `sub/../secret`, `./secret` and a symlink to `secret` all normalize to the same resource.
public struct PermissionRuleSubject: Sendable, Hashable {
    public var action: String
    public var resource: String

    public init(action: String, resource: String) {
        self.action = action
        self.resource = resource
    }

    /// Tool name → the argument key holding the path resource.
    private static let pathArgumentKeyByTool: [String: String] = [
        "host.file.read": "path",
        "host.file.write": "path",
        "host.file.list": "path",
        "host.file.search": "path"
    ]

    private static let shellRunToolName = "host.shell.run"
    private static let mcpCallToolName = "host.mcp.call"

    public static func make(toolCall: ToolCall, workspaceRoot: URL?) -> PermissionRuleSubject {
        let arguments = try? ToolArguments(toolCall.argumentsJSON)
        let resource: String
        if toolCall.name == shellRunToolName {
            resource = normalizedCommand(arguments?.string("cmd"))
        } else if let pathKey = pathArgumentKeyByTool[toolCall.name] {
            resource = normalizedPath(arguments?.string(pathKey), workspaceRoot: workspaceRoot)
        } else if toolCall.name == mcpCallToolName {
            resource = mcpResource(arguments)
        } else {
            // Tools without a natural single resource are matched at the action level: the
            // derived rule saves resource "" and pattern rules use "" / "*" / "**" (all of which
            // match the empty resource).
            resource = ""
        }
        return PermissionRuleSubject(action: toolCall.name, resource: resource)
    }

    /// Trims and collapses whitespace runs (spaces, tabs, newlines) to single spaces so `rm  -rf x`
    /// cannot dodge a rule saved for `rm -rf x`.
    static func normalizedCommand(_ command: String?) -> String {
        guard let command else { return "" }
        return command
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Absolute, `..`-resolved, symlink-resolved path (via the shared `WorkspaceBoundary`
    /// normalization the file/git/patch executors enforce). Relative paths resolve against the
    /// workspace root; without a root the path is lexically standardized only.
    static func normalizedPath(_ path: String?, workspaceRoot: URL?) -> String {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = trimmed.isEmpty ? "." : trimmed
        let candidate: URL
        if effective.hasPrefix("/") {
            candidate = URL(fileURLWithPath: effective)
        } else if let workspaceRoot {
            candidate = workspaceRoot.appendingPathComponent(effective)
        } else {
            // No workspace root to resolve against (rule tables are per-workspace, so evaluation
            // always has one; this is a defensive fallback). Leave the spelling as-is rather than
            // absolutizing against an unrelated current directory.
            return effective
        }
        return WorkspaceBoundary.symlinkResolvedPath(candidate.standardizedFileURL)
    }

    /// `serverID/toolName` — the `/` separator keeps `*` scoped to one side (`github/*` allows one
    /// server's tools without allowing every server).
    private static func mcpResource(_ arguments: ToolArguments?) -> String {
        let server = arguments?.string("serverID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tool = arguments?.string("toolName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !server.isEmpty || !tool.isEmpty else { return "" }
        return "\(server)/\(tool)"
    }
}

public enum PermissionRuleDerivation {
    /// Derives the rule an "always allow/deny" answer persists for an approval request: the EXACT
    /// tool name and the EXACT normalized resource, never auto-generalized to a wildcard — the
    /// user teaches one operation at a time; broader patterns are a deliberate hand-edit.
    public static func rule(
        for request: ApprovalRequest,
        decision: PermissionRuleDecision,
        workspaceRoot: URL?
    ) -> PermissionRule {
        let subject = PermissionRuleSubject.make(toolCall: request.toolCall, workspaceRoot: workspaceRoot)
        return PermissionRule(
            action: subject.action,
            resource: subject.resource,
            match: .exact,
            decision: decision
        )
    }
}
