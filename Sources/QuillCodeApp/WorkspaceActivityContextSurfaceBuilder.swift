import Foundation
import QuillCodeCore

enum WorkspaceActivityContextSurfaceBuilder {
    static func items(for thread: ChatThread) -> [ActivityItemSurface] {
        thread.events
            .compactMap(item(for:))
            .suffix(6)
    }

    private static func item(for event: ThreadEvent) -> ActivityItemSurface? {
        guard event.kind == .notice else { return nil }
        if let telemetry = telemetry(from: event) {
            return item(for: telemetry, eventID: event.id.uuidString)
        }
        return noticeItem(for: event)
    }

    private static func item(
        for telemetry: WorkspaceContextSummaryTelemetry,
        eventID: String
    ) -> ActivityItemSurface {
        ActivityItemSurface(
            id: "context-\(eventID)",
            title: continuationTitle(for: telemetry),
            detail: continuationDetail(for: telemetry),
            kind: "context",
            // Only a genuine fallback is "checked" (a degraded outcome worth a second look). A model
            // summary and a deliberate E2E-private local summary are both simply done.
            statusLabel: telemetry.source == .deterministicFallback
                ? ActivityStatusLabel.checked
                : ActivityStatusLabel.done
        )
    }

    private static func noticeItem(for event: ThreadEvent) -> ActivityItemSurface? {
        guard let presentation = noticePresentation(for: event.summary) else { return nil }
        return ActivityItemSurface(
            id: "context-\(event.id.uuidString)",
            title: presentation.title,
            detail: presentation.detail,
            kind: "context",
            statusLabel: presentation.statusLabel
        )
    }

    private static func noticePresentation(for summary: String) -> NoticePresentation? {
        switch summary {
        case WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact):
            return NoticePresentation(
                title: "Compacting context",
                detail: "Asking TrustedRouter for a durable continuation summary.",
                statusLabel: ActivityStatusLabel.running
            )
        case WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary):
            return NoticePresentation(
                title: "Summarizing fork context",
                detail: "Asking TrustedRouter for a fork-ready summary.",
                statusLabel: ActivityStatusLabel.running
            )
        // The local (E2E) start variants need their OWN copy: the two above promise a TrustedRouter
        // call that an E2E-routed summary never makes, and this notice persists in Activity next to
        // the "never reached an auxiliary model" finish notice.
        case WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact, isLocal: true):
            return NoticePresentation(
                title: "Compacting context",
                detail: "Summarizing on-device to keep this end-to-end-encrypted chat private.",
                statusLabel: ActivityStatusLabel.running
            )
        case WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary, isLocal: true):
            return NoticePresentation(
                title: "Summarizing fork context",
                detail: "Summarizing on-device to keep this end-to-end-encrypted chat private.",
                statusLabel: ActivityStatusLabel.running
            )
        case WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
            outcome: WorkspaceContextSummaryOutcome(summaryOverride: "", source: .model),
            purpose: .compact
        ):
            return NoticePresentation(
                title: "Context summary ready",
                detail: "Model summary ready for compacted continuation.",
                statusLabel: ActivityStatusLabel.done
            )
        case WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
            outcome: WorkspaceContextSummaryOutcome(summaryOverride: "", source: .model),
            purpose: .forkSummary
        ):
            return NoticePresentation(
                title: "Fork summary ready",
                detail: "Model summary ready for forked continuation.",
                statusLabel: ActivityStatusLabel.done
            )
        case WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
            outcome: WorkspaceContextSummaryOutcome(
                summaryOverride: nil,
                source: .deterministicFallback
            ),
            purpose: .compact
        ):
            return NoticePresentation(
                title: "Deterministic fallback used",
                detail: "Model context summary was unavailable, so QuillCode kept a local fallback summary.",
                statusLabel: ActivityStatusLabel.checked
            )
        case WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
            outcome: WorkspaceContextSummaryOutcome(
                summaryOverride: nil,
                source: .deterministicFallback
            ),
            purpose: .forkSummary
        ):
            return NoticePresentation(
                title: "Fork fallback used",
                detail: "Model fork summary was unavailable, so QuillCode kept a local fallback summary.",
                statusLabel: ActivityStatusLabel.checked
            )
        case WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
            outcome: WorkspaceContextSummaryOutcome(
                summaryOverride: nil,
                source: .e2eDeterministic
            ),
            purpose: .compact
        ):
            return NoticePresentation(
                title: "Compacted privately",
                detail: "Summarized locally so this end-to-end-encrypted chat never reached an auxiliary model.",
                statusLabel: ActivityStatusLabel.done
            )
        case WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
            outcome: WorkspaceContextSummaryOutcome(
                summaryOverride: nil,
                source: .e2eDeterministic
            ),
            purpose: .forkSummary
        ):
            return NoticePresentation(
                title: "Fork summarized privately",
                detail: "Summarized locally so this end-to-end-encrypted chat never reached an auxiliary model.",
                statusLabel: ActivityStatusLabel.done
            )
        default:
            return nil
        }
    }

    private static func telemetry(from event: ThreadEvent) -> WorkspaceContextSummaryTelemetry? {
        guard let payload = event.payloadJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkspaceContextSummaryTelemetry.self, from: payload)
    }

    private static func continuationTitle(for telemetry: WorkspaceContextSummaryTelemetry) -> String {
        switch (telemetry.purpose, telemetry.source) {
        case (.compact, .model):
            return "Context compacted"
        case (.forkSummary, .model):
            return "Fork summary ready"
        case (.compact, .deterministicFallback):
            return "Context compacted with fallback"
        case (.forkSummary, .deterministicFallback):
            return "Fork summary fallback used"
        case (.compact, .e2eDeterministic):
            return "Context compacted privately"
        case (.forkSummary, .e2eDeterministic):
            return "Fork summarized privately"
        }
    }

    private static func continuationDetail(for telemetry: WorkspaceContextSummaryTelemetry) -> String {
        var detailParts = [
            sourceLabel(for: telemetry.source),
            "from \(telemetry.sourceTitle)"
        ]
        if let summaryCharacterCount = telemetry.summaryCharacterCount {
            detailParts.append("\(summaryCharacterCount) characters")
        }
        if let errorDescription = telemetry.errorDescription, !errorDescription.isEmpty {
            detailParts.append("Fallback reason: \(errorDescription)")
        }
        return WorkspaceActivityText.boundedLine(detailParts.joined(separator: " · "), limit: 140)
    }

    private static func sourceLabel(for source: WorkspaceContextSummaryOutcomeSource) -> String {
        switch source {
        case .model:
            return "Model summary"
        case .deterministicFallback:
            return "Deterministic summary"
        case .e2eDeterministic:
            return "Local summary (end-to-end encrypted)"
        }
    }

    private struct NoticePresentation {
        var title: String
        var detail: String
        var statusLabel: String
    }
}
