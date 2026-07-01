import Foundation

public enum WorkspaceContextSummaryOutcomeSource: String, Codable, Sendable, Hashable {
    case model
    case deterministicFallback = "deterministic_fallback"
}

public struct WorkspaceContextSummaryOutcome: Sendable, Hashable {
    public var summaryOverride: String?
    public var source: WorkspaceContextSummaryOutcomeSource
    public var errorDescription: String?

    public init(
        summaryOverride: String?,
        source: WorkspaceContextSummaryOutcomeSource,
        errorDescription: String? = nil
    ) {
        self.summaryOverride = summaryOverride
        self.source = source
        self.errorDescription = errorDescription
    }
}
