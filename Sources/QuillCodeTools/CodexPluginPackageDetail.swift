import Foundation

/// Bounded, data-only capabilities discovered from one local Codex plugin package.
public struct CodexPluginPackageDetail: Sendable, Hashable {
    public var skills: [SkillCatalogMetadata]
    public var hooks: [CodexPluginHookDeclaration]
    public var apps: [CodexPluginAppDeclaration]
    public var mcpServerNames: [String]

    public init(
        skills: [SkillCatalogMetadata] = [],
        hooks: [CodexPluginHookDeclaration] = [],
        apps: [CodexPluginAppDeclaration] = [],
        mcpServerNames: [String] = []
    ) {
        self.skills = skills
        self.hooks = hooks
        self.apps = apps
        self.mcpServerNames = mcpServerNames
    }
}

public struct CodexPluginHookDeclaration: Sendable, Hashable {
    public var key: String
    public var event: CodexPluginHookEvent

    public init(key: String, event: CodexPluginHookEvent) {
        self.key = key
        self.event = event
    }
}

/// Codex app-server spelling for the supported hook event set.
public enum CodexPluginHookEvent: String, CaseIterable, Sendable, Hashable {
    case preToolUse
    case permissionRequest
    case postToolUse
    case preCompact
    case postCompact
    case sessionStart
    case userPromptSubmit
    case subagentStart
    case subagentStop
    case stop

    var manifestName: String {
        switch self {
        case .preToolUse: "PreToolUse"
        case .permissionRequest: "PermissionRequest"
        case .postToolUse: "PostToolUse"
        case .preCompact: "PreCompact"
        case .postCompact: "PostCompact"
        case .sessionStart: "SessionStart"
        case .userPromptSubmit: "UserPromptSubmit"
        case .subagentStart: "SubagentStart"
        case .subagentStop: "SubagentStop"
        case .stop: "Stop"
        }
    }

    var keyLabel: String {
        switch self {
        case .preToolUse: "pre_tool_use"
        case .permissionRequest: "permission_request"
        case .postToolUse: "post_tool_use"
        case .preCompact: "pre_compact"
        case .postCompact: "post_compact"
        case .sessionStart: "session_start"
        case .userPromptSubmit: "user_prompt_submit"
        case .subagentStart: "subagent_start"
        case .subagentStop: "subagent_stop"
        case .stop: "stop"
        }
    }

    init?(manifestName: String) {
        guard let event = Self.allCases.first(where: { $0.manifestName == manifestName }) else {
            return nil
        }
        self = event
    }
}

public struct CodexPluginAppDeclaration: Sendable, Hashable {
    public var id: String
    public var name: String
    public var category: String?

    public init(id: String, name: String, category: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
    }
}
