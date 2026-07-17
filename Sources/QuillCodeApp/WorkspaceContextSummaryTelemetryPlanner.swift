import Foundation
import QuillCodeCore

struct WorkspaceContextSummaryTelemetryPlanner {
    /// `isLocal` marks a summary that will be produced on-device because the thread is routed to the
    /// E2E model. Without it the start notice claims "with TrustedRouter" for a call that never
    /// happens — and sits in Activity forever contradicting the "never reached an auxiliary model"
    /// finish notice. Defaulted so every existing caller and string-match pattern is unchanged.
    static func sourceStartSummary(
        purpose: WorkspaceContextSummaryPurpose,
        isLocal: Bool = false
    ) -> String {
        switch (purpose, isLocal) {
        case (.compact, false):
            return "Compacting context with TrustedRouter"
        case (.forkSummary, false):
            return "Summarizing context with TrustedRouter"
        case (.compact, true):
            return "Compacting context locally"
        case (.forkSummary, true):
            return "Summarizing context locally"
        }
    }

    static func sourceFinishedSummary(
        outcome: WorkspaceContextSummaryOutcome,
        purpose: WorkspaceContextSummaryPurpose
    ) -> String {
        switch (purpose, outcome.source) {
        case (.compact, .model):
            return "Model context summary ready"
        case (.forkSummary, .model):
            return "Model fork summary ready"
        case (.compact, .deterministicFallback):
            return "Model context summary unavailable; used deterministic fallback"
        case (.forkSummary, .deterministicFallback):
            return "Model fork summary unavailable; used deterministic fallback"
        case (.compact, .e2eDeterministic):
            return "Summarized locally to keep this end-to-end-encrypted chat private"
        case (.forkSummary, .e2eDeterministic):
            return "Summarized the fork locally to keep this end-to-end-encrypted chat private"
        }
    }

    static func continuationEvent(
        outcome: WorkspaceContextSummaryOutcome,
        sourceTitle: String,
        purpose: WorkspaceContextSummaryPurpose
    ) -> ThreadEvent {
        ThreadEvent(
            kind: .notice,
            summary: continuationSummary(outcome: outcome, purpose: purpose),
            payloadJSON: telemetryPayload(
                outcome: outcome,
                sourceTitle: sourceTitle,
                purpose: purpose
            )
        )
    }

    private static func continuationSummary(
        outcome: WorkspaceContextSummaryOutcome,
        purpose: WorkspaceContextSummaryPurpose
    ) -> String {
        switch (purpose, outcome.source) {
        case (.compact, .model):
            return "Used model context summary"
        case (.forkSummary, .model):
            return "Used model fork summary"
        case (.compact, .deterministicFallback):
            return "Used deterministic context summary fallback"
        case (.forkSummary, .deterministicFallback):
            return "Used deterministic fork summary fallback"
        case (.compact, .e2eDeterministic):
            return "Used a local context summary to keep this end-to-end-encrypted chat private"
        case (.forkSummary, .e2eDeterministic):
            return "Used a local fork summary to keep this end-to-end-encrypted chat private"
        }
    }

    private static func telemetryPayload(
        outcome: WorkspaceContextSummaryOutcome,
        sourceTitle: String,
        purpose: WorkspaceContextSummaryPurpose
    ) -> String? {
        try? JSONHelpers.encodePretty(WorkspaceContextSummaryTelemetry(
            purpose: purpose,
            source: outcome.source,
            sourceTitle: sourceTitle,
            summaryCharacterCount: outcome.summaryOverride?.count,
            errorDescription: outcome.errorDescription,
            modelID: outcome.modelSelection?.modelID,
            modelSelectionSource: outcome.modelSelection?.source
        ))
    }
}
