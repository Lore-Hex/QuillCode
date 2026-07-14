import Foundation
import QuillCodeCore

enum ProjectPluginSessionStartSource: String, Sendable, Hashable {
    case startup
    case resume
    case clear
    case compact
}

struct ProjectPluginSubagentHookContext: Sendable, Hashable {
    var parentThread: ChatThread
    var agentID: String
    var agentType: String
    var transcriptPath: String?
}

enum ProjectPluginLifecycleHookEvent: Sendable, Hashable {
    case sessionStart(ProjectPluginSessionStartSource)
    case subagentStart(ProjectPluginSubagentHookContext)
    case subagentStop(
        ProjectPluginSubagentHookContext,
        stopHookActive: Bool,
        lastAssistantMessage: String?
    )

    var name: String {
        switch self {
        case .sessionStart: "SessionStart"
        case .subagentStart: "SubagentStart"
        case .subagentStop: "SubagentStop"
        }
    }

    var matcherCandidate: String {
        switch self {
        case .sessionStart(let source): source.rawValue
        case .subagentStart(let context), .subagentStop(let context, _, _): context.agentType
        }
    }

    var includesTurnID: Bool {
        if case .sessionStart = self { return false }
        return true
    }

    func inputThread(sessionThread: ChatThread) -> ChatThread {
        switch self {
        case .sessionStart:
            sessionThread
        case .subagentStart(let context), .subagentStop(let context, _, _):
            context.parentThread
        }
    }

    var acceptsPlainTextContext: Bool {
        switch self {
        case .sessionStart, .subagentStart: true
        case .subagentStop: false
        }
    }

    var ignoresContinueFalse: Bool {
        if case .subagentStart = self { return true }
        return false
    }
}

struct ProjectPluginLifecycleHookContext: Sendable, Hashable {
    var hook: ProjectPluginHook
    var content: String
}

struct ProjectPluginLifecycleHookReport: Sendable, Hashable {
    var contexts: [ProjectPluginLifecycleHookContext] = []
    var notices: [String] = []
    var continues = true
    var stopReason: String?
    var continuationReason: String?
}

struct ProjectPluginLifecycleHookSemanticOutput: Sendable, Hashable {
    var additionalContext: String?
    var systemMessage: String?
    var continues = true
    var stopReason: String?
    var continuationReason: String?
}
