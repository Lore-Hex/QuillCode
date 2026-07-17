import Foundation
import QuillCodeAgent

/// `CaseIterable` so the banner/Activity string-matchers — which clear the progress spinner by
/// matching planner copy behind a `default:` — can be regression-tested against EVERY source. Adding
/// a case without teaching those matchers silently wedges the context banner; the exhaustive test is
/// what catches it.
public enum WorkspaceContextSummaryOutcomeSource: String, Codable, Sendable, Hashable, CaseIterable {
    case model
    case deterministicFallback = "deterministic_fallback"
    /// The summary was produced locally ON PURPOSE: the thread is routed to the end-to-end-encrypted
    /// model, so its transcript must never reach a non-E2E auxiliary summary model. Deliberately
    /// distinct from `deterministicFallback`, which means the model summary genuinely failed — the
    /// two read very differently to a user auditing why their chat was summarized locally.
    case e2eDeterministic = "e2e_deterministic"
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
