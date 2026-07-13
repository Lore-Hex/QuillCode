import Foundation

/// Session-only behavior attached to a chat thread.
///
/// Runtime context is intentionally not encoded by `ChatThread`. Ephemeral threads must never
/// survive a relaunch or leak into the durable thread store as ordinary conversations.
public enum ThreadRuntimeContext: Sendable, Hashable {
    case standard
    case sideConversation(parentThreadID: UUID)

    public var isEphemeral: Bool {
        if case .sideConversation = self { return true }
        return false
    }

    public var sideConversationParentThreadID: UUID? {
        guard case .sideConversation(let parentThreadID) = self else { return nil }
        return parentThreadID
    }
}
