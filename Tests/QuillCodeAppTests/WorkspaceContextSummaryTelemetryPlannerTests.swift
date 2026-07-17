import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceContextSummaryTelemetryPlannerTests: XCTestCase {
    func testContinuationEventRecordsModelSummaryTelemetry() throws {
        let event = WorkspaceContextSummaryTelemetryPlanner.continuationEvent(
            outcome: WorkspaceContextSummaryOutcome(
                summaryOverride: "Keep the important state.",
                source: .model
            ),
            sourceTitle: "Large thread",
            purpose: .compact
        )
        let telemetry = try XCTUnwrap(decodeTelemetry(event))

        XCTAssertEqual(event.kind, .notice)
        XCTAssertEqual(event.summary, "Used model context summary")
        XCTAssertEqual(telemetry.purpose, .compact)
        XCTAssertEqual(telemetry.source, .model)
        XCTAssertEqual(telemetry.sourceTitle, "Large thread")
        XCTAssertEqual(telemetry.summaryCharacterCount, "Keep the important state.".count)
        XCTAssertNil(telemetry.errorDescription)
    }

    func testContinuationEventRecordsFallbackTelemetry() throws {
        let event = WorkspaceContextSummaryTelemetryPlanner.continuationEvent(
            outcome: WorkspaceContextSummaryOutcome(
                summaryOverride: nil,
                source: .deterministicFallback,
                errorDescription: "summary timeout"
            ),
            sourceTitle: "Fork thread",
            purpose: .forkSummary
        )
        let telemetry = try XCTUnwrap(decodeTelemetry(event))

        XCTAssertEqual(event.summary, "Used deterministic fork summary fallback")
        XCTAssertEqual(telemetry.purpose, .forkSummary)
        XCTAssertEqual(telemetry.source, .deterministicFallback)
        XCTAssertEqual(telemetry.errorDescription, "summary timeout")
        XCTAssertNil(telemetry.summaryCharacterCount)
    }

    func testSourceNoticeCopySeparatesPurposeAndOutcome() {
        XCTAssertEqual(
            WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact),
            "Compacting context with TrustedRouter"
        )
        XCTAssertEqual(
            WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary),
            "Summarizing context with TrustedRouter"
        )
        XCTAssertEqual(
            WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(summaryOverride: "ok", source: .model),
                purpose: .forkSummary
            ),
            "Model fork summary ready"
        )
        XCTAssertEqual(
            WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(
                    summaryOverride: nil,
                    source: .deterministicFallback,
                    errorDescription: "failed"
                ),
                purpose: .compact
            ),
            "Model context summary unavailable; used deterministic fallback"
        )
    }

    func testContinuationEventRecordsE2EPrivateSummaryTelemetry() throws {
        let event = WorkspaceContextSummaryTelemetryPlanner.continuationEvent(
            outcome: WorkspaceContextSummaryOutcome(
                summaryOverride: "Local summary of the private chat.",
                source: .e2eDeterministic
            ),
            sourceTitle: "E2E thread",
            purpose: .compact
        )
        let telemetry = try XCTUnwrap(decodeTelemetry(event))

        XCTAssertEqual(
            event.summary,
            "Used a local context summary to keep this end-to-end-encrypted chat private",
            "an E2E summary is local by DESIGN — it must never read as a failed/unavailable model summary"
        )
        XCTAssertEqual(telemetry.source, .e2eDeterministic)
        XCTAssertNil(telemetry.errorDescription, "nothing failed, so there is no fallback reason to report")
    }

    func testLocalStartNoticeDoesNotPromiseATrustedRouterCall() {
        for purpose in [WorkspaceContextSummaryPurpose.compact, .forkSummary] {
            let local = WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: purpose, isLocal: true)
            XCTAssertFalse(local.contains("TrustedRouter"), "an E2E summary never calls it: \(local)")
            XCTAssertTrue(local.contains("locally"), local)
            // The default (non-local) copy is unchanged, so existing notices keep matching.
            XCTAssertTrue(
                WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: purpose)
                    .contains("with TrustedRouter")
            )
        }
    }

    func testE2EPrivateSourceNoticeCopyExplainsPrivacyNotFailure() {
        for (purpose, expected) in [
            (WorkspaceContextSummaryPurpose.compact, "Summarized locally to keep this end-to-end-encrypted chat private"),
            (.forkSummary, "Summarized the fork locally to keep this end-to-end-encrypted chat private")
        ] {
            let copy = WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(summaryOverride: "ok", source: .e2eDeterministic),
                purpose: purpose
            )
            XCTAssertEqual(copy, expected)
            XCTAssertFalse(copy.contains("unavailable"), "the model summary was skipped on purpose, not unavailable")
            XCTAssertFalse(copy.contains("fallback"), copy)
        }
    }

    private func decodeTelemetry(_ event: ThreadEvent) throws -> WorkspaceContextSummaryTelemetry? {
        guard let payload = event.payloadJSON?.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(WorkspaceContextSummaryTelemetry.self, from: payload)
    }
}
