import Foundation

public struct DeferredThreadPayloadSummary: Sendable, Hashable {
    public var searchText: String
    public var attachmentIDs: Set<UUID>
    public var agentImportProvenance: AgentImportThreadProvenance?
    public var attentionItem: AttentionItem?
    public var periodUsage: ThreadPeriodUsageSnapshot?

    public init(
        searchText: String,
        attachmentIDs: Set<UUID> = [],
        agentImportProvenance: AgentImportThreadProvenance? = nil,
        attentionItem: AttentionItem? = nil,
        periodUsage: ThreadPeriodUsageSnapshot? = nil
    ) {
        self.searchText = searchText
        self.attachmentIDs = attachmentIDs
        self.agentImportProvenance = agentImportProvenance
        self.attentionItem = attentionItem
        self.periodUsage = periodUsage
    }
}

/// Runtime-only ownership for a persisted chat's potentially large transcript payload.
/// Deferred summaries keep navigation metadata, bounded search text, and compact period accounting
/// in memory; persistence hydrates the authoritative chat before transcript access or mutation.
public enum ThreadPayloadResidency: Sendable, Hashable {
    case loaded
    case deferred(DeferredThreadPayloadSummary)

    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    public var deferredSearchText: String? {
        deferredSummary?.searchText
    }

    public var deferredSummary: DeferredThreadPayloadSummary? {
        guard case .deferred(let summary) = self else { return nil }
        return summary
    }
}
