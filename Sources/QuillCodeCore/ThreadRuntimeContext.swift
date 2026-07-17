import Foundation

/// Session-only behavior attached to a chat thread.
///
/// Runtime context is intentionally not encoded by `ChatThread`. Ephemeral threads must never
/// survive a relaunch or leak into the durable thread store as ordinary conversations.
public enum ThreadRuntimeContext: Sendable, Hashable {
    case standard
    case sideConversation(parentThreadID: UUID)
    // NOTE: append new cases at the end only — inserting mid-enum shifts case discriminants and
    // corrupts incremental builds of already-compiled modules.
    case confidential

    public var isEphemeral: Bool {
        if case .sideConversation = self { return true }
        if case .confidential = self { return true }
        return false
    }

    /// Confidential threads are the strictest ephemeral flavor: nothing about them may reach disk, and
    /// their model is pinned to the end-to-end-encrypted TrustedRouter route for the thread's lifetime.
    public var isConfidential: Bool {
        if case .confidential = self { return true }
        return false
    }

    public var sideConversationParentThreadID: UUID? {
        guard case .sideConversation(let parentThreadID) = self else { return nil }
        return parentThreadID
    }
}
