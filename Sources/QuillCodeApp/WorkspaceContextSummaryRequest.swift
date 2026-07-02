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
    /// The auxiliary model this summary should run on (see `AuxiliaryModelSelector`). nil keeps the
    /// generator's configured client untouched.
    public var modelID: String?

    init(
        sourceTitle: String,
        context: WorkspaceContextSummaryContext,
        purpose: WorkspaceContextSummaryPurpose,
        modelID: String? = nil
    ) {
        self.sourceTitle = sourceTitle
        olderMessages = context.olderMessages
        recentMessages = context.recentMessages
        self.purpose = purpose
        self.modelID = modelID
    }
}
