import Foundation
import QuillCodeAgent

public enum WorkspaceContextSummaryOutcomeSource: String, Codable, Sendable, Hashable {
    case model
    case deterministicFallback = "deterministic_fallback"
}

public struct WorkspaceContextSummaryOutcome: Sendable, Hashable {
    public var summaryOverride: String?
    public var source: WorkspaceContextSummaryOutcomeSource
    public var errorDescription: String?
    /// The auxiliary model the summary call was directed at, and why it was chosen — carried into
    /// the continuation event's telemetry payload so the choice is auditable per thread.
    public var modelSelection: AuxiliaryModelSelection?

    public init(
        summaryOverride: String?,
        source: WorkspaceContextSummaryOutcomeSource,
        errorDescription: String? = nil,
        modelSelection: AuxiliaryModelSelection? = nil
    ) {
        self.summaryOverride = summaryOverride
        self.source = source
        self.errorDescription = errorDescription
        self.modelSelection = modelSelection
    }
}
