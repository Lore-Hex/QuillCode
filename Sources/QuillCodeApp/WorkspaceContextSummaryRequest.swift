import Foundation
import QuillCodeCore

struct WorkspaceContextSummaryContext: Sendable, Hashable {
    var olderMessages: [ChatMessage]
    var recentMessages: [ChatMessage]
}

public struct WorkspaceContextSummaryRequest: Sendable, Hashable {
    public var sourceTitle: String
    public var olderMessages: [ChatMessage]
    public var recentMessages: [ChatMessage]
    public var purpose: WorkspaceContextSummaryPurpose

    init(
        sourceTitle: String,
        context: WorkspaceContextSummaryContext,
        purpose: WorkspaceContextSummaryPurpose
    ) {
        self.sourceTitle = sourceTitle
        olderMessages = context.olderMessages
        recentMessages = context.recentMessages
        self.purpose = purpose
    }
}
