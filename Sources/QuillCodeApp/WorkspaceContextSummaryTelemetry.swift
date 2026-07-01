import Foundation

public struct WorkspaceContextSummaryTelemetry: Codable, Sendable, Hashable {
    public var purpose: WorkspaceContextSummaryPurpose
    public var source: WorkspaceContextSummaryOutcomeSource
    public var sourceTitle: String
    public var summaryCharacterCount: Int?
    public var errorDescription: String?

    public init(
        purpose: WorkspaceContextSummaryPurpose,
        source: WorkspaceContextSummaryOutcomeSource,
        sourceTitle: String,
        summaryCharacterCount: Int? = nil,
        errorDescription: String? = nil
    ) {
        self.purpose = purpose
        self.source = source
        self.sourceTitle = sourceTitle
        self.summaryCharacterCount = summaryCharacterCount
        self.errorDescription = errorDescription
    }
}
