import Foundation
import QuillCodeCore

/// The bounded result of trusted `PreToolUse` hooks. Hooks may rewrite only the arguments of the
/// current call; the app-level adapter validates that rewrite before constructing this value.
public struct AgentPreToolUseHookOutcome: Sendable, Hashable {
    public var call: ToolCall
    public var blockedReason: String?
    public var additionalContexts: [String]
    public var notices: [String]

    public init(
        call: ToolCall,
        blockedReason: String? = nil,
        additionalContexts: [String] = [],
        notices: [String] = []
    ) {
        self.call = call
        self.blockedReason = blockedReason
        self.additionalContexts = additionalContexts
        self.notices = notices
    }
}

/// The bounded result of trusted `PostToolUse` hooks. A replacement result changes only the
/// model-facing feedback; it cannot roll back a side effect that the tool already completed.
public struct AgentPostToolUseHookOutcome: Sendable, Hashable {
    public var result: ToolResult
    public var additionalContexts: [String]
    public var notices: [String]

    public init(
        result: ToolResult,
        additionalContexts: [String] = [],
        notices: [String] = []
    ) {
        self.result = result
        self.additionalContexts = additionalContexts
        self.notices = notices
    }
}

/// A trusted `PermissionRequest` hook may suppress the ordinary approval UI only by making an
/// explicit allow or deny decision. Missing, invalid, and failed hook output maps to
/// `noDecision`, preserving QuillCode's normal durable approval flow.
public enum AgentPermissionRequestDecision: Sendable, Hashable {
    case noDecision
    case allow
    case deny(reason: String)
}

public struct AgentPermissionRequestHookOutcome: Sendable, Hashable {
    public var decision: AgentPermissionRequestDecision
    public var notices: [String]

    public init(
        decision: AgentPermissionRequestDecision = .noDecision,
        notices: [String] = []
    ) {
        self.decision = decision
        self.notices = notices
    }
}

public typealias AgentPreToolUseHook = @Sendable (
    ToolCall,
    ChatThread,
    URL
) async throws -> AgentPreToolUseHookOutcome

public typealias AgentPostToolUseHook = @Sendable (
    ToolCall,
    ToolResult,
    ChatThread,
    URL
) async throws -> AgentPostToolUseHookOutcome

public typealias AgentPermissionRequestHook = @Sendable (
    ToolCall,
    String,
    ChatThread,
    URL
) async throws -> AgentPermissionRequestHookOutcome
