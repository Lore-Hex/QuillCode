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

    private func decodeTelemetry(_ event: ThreadEvent) throws -> WorkspaceContextSummaryTelemetry? {
        guard let payload = event.payloadJSON?.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(WorkspaceContextSummaryTelemetry.self, from: payload)
    }
}
