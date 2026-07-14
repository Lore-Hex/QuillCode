import Foundation
import QuillCodeCore

/// Identifies why a compaction lifecycle started. Standard plugin matchers receive this raw value.
public enum AgentCompactionTrigger: String, Sendable, Hashable {
    case manual
    case auto
}

/// The bounded result of one trusted compaction hook stage. A false `continues` value is the only
/// semantic stop signal; command failures are converted into notices by the app adapter.
public struct AgentCompactionHookOutcome: Sendable, Hashable {
    public var continues: Bool
    public var stopReason: String?
    public var notices: [String]

    public init(
        continues: Bool = true,
        stopReason: String? = nil,
        notices: [String] = []
    ) {
        self.continues = continues
        self.stopReason = stopReason
        self.notices = notices
    }
}

public typealias AgentCompactionHook = @Sendable (
    AgentCompactionTrigger,
    ChatThread,
    URL
) async throws -> AgentCompactionHookOutcome

public enum AgentCompactionHookStage: String, Sendable, Hashable {
    case before
    case after
}

/// Raised only for an explicit `continue: false` response. Before-stage stops leave the thread
/// untouched; after-stage stops preserve the completed compaction but stop the active agent turn.
public struct AgentCompactionHookStoppedError: LocalizedError, CustomStringConvertible, Sendable {
    public var trigger: AgentCompactionTrigger
    public var stage: AgentCompactionHookStage
    public var reason: String

    public init(
        trigger: AgentCompactionTrigger,
        stage: AgentCompactionHookStage,
        reason: String
    ) {
        self.trigger = trigger
        self.stage = stage
        self.reason = reason
    }

    public var description: String {
        "Compaction stopped \(stage.rawValue) it ran: \(reason)"
    }

    public var errorDescription: String? { description }
}
