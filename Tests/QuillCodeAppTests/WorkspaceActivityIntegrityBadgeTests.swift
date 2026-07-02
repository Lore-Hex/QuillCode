import XCTest
import QuillCodeCore
@testable import QuillCodeApp

/// The Activity-surface half of #875: the recorded run-integrity verdict shows up as a badge on the
/// Activity surface (SwiftUI header + HTML), and only once a verdict has actually been recorded.
final class WorkspaceActivityIntegrityBadgeTests: XCTestCase {
    private func thread(recording verdict: RunIntegrityVerdict?, detail: String? = nil) -> ChatThread {
        var t = ChatThread(title: "Fix parser", messages: [ChatMessage(role: .assistant, content: "done")])
        if let verdict {
            let report = RunIntegrityReport(verdict: verdict, reasons: reasons(for: verdict, detail: detail))
            if let event = RunIntegrityRecord.event(for: report) {
                t.events.append(event)
            }
        }
        return t
    }

    /// A reason whose rule matches the verdict so `RunIntegrityReport.summaryLine` (which the badge
    /// detail reads) surfaces the supplied detail text.
    private func reasons(for verdict: RunIntegrityVerdict, detail: String?) -> [RunIntegrityReason] {
        guard let detail else { return [] }
        switch verdict {
        case .verified:
            return [RunIntegrityReason(rule: .backedSuccessClaim, detail: detail)]
        case .unverified:
            return [RunIntegrityReason(rule: .unbackedSuccessClaim, detail: detail)]
        case .red:
            return [RunIntegrityReason(rule: .standingTestFailure, detail: detail)]
        }
    }

    private func surface(for thread: ChatThread) -> WorkspaceActivitySurface {
        WorkspaceActivitySurface(
            isVisible: true,
            thread: thread,
            toolCards: [],
            instructions: [],
            memories: [],
            agentStatus: "Done"
        )
    }

    func testNoBadgeUntilAVerdictIsRecorded() {
        let s = surface(for: thread(recording: nil))
        XCTAssertNil(s.integrityBadge)
        XCTAssertTrue(s.integrityDetail.isEmpty)
    }

    func testRecordedRedVerdictSurfacesAsBadge() {
        let s = surface(for: thread(recording: .red, detail: "swift test failed and was not re-run"))
        XCTAssertEqual(s.integrityBadge, .red)
        XCTAssertEqual(s.integrityDetail, "swift test failed and was not re-run")
    }

    func testRecordedVerifiedVerdictSurfacesAsBadge() {
        XCTAssertEqual(surface(for: thread(recording: .verified)).integrityBadge, .verified)
    }

    func testBadgeRendersInHTMLWithVerdictAttribute() {
        let s = surface(for: thread(recording: .unverified, detail: "claimed pass, no test ran"))
        let html = WorkspaceHTMLActivityPaneRenderer.render(s)
        XCTAssertTrue(html.contains(#"data-testid="activity-integrity""#), html)
        XCTAssertTrue(html.contains(#"data-integrity="unverified""#), html)
        XCTAssertTrue(html.contains("UNVERIFIED"), html)
        XCTAssertTrue(html.contains("claimed pass, no test ran"), html)
    }

    func testNoBadgeElementInHTMLWhenUnrecorded() {
        let html = WorkspaceHTMLActivityPaneRenderer.render(surface(for: thread(recording: nil)))
        XCTAssertFalse(html.contains(#"data-testid="activity-integrity""#), html)
    }

    func testBadgeSurvivesActivitySurfaceCodableRoundTrip() throws {
        let s = surface(for: thread(recording: .red, detail: "boom"))
        let data = try JSONEncoder().encode(s)
        let reloaded = try JSONDecoder().decode(WorkspaceActivitySurface.self, from: data)
        XCTAssertEqual(reloaded.integrityBadge, .red)
        XCTAssertEqual(reloaded.integrityDetail, "boom")
    }
}
