import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

/// In a headless autonomous run (--sandbox workspace-write) there is no human to answer an approval
/// prompt, so a `.clarify` must become `.approve` — otherwise the run dead-ends at the first
/// unrecognized-but-safe setup command (a plain `git clone` / `uv venv`), which is what stalled
/// coworker use case #1 after the deferral-stall fix let it get that far. The safety boundary is
/// unchanged: `.deny` (hard-deny floors) is never converted.
final class AutonomousApprovalSafetyReviewerTests: XCTestCase {
    private struct FixedReviewer: SafetyReviewer {
        let verdict: ApprovalVerdict
        func review(_ context: SafetyContext) async -> SafetyReview {
            SafetyReview(verdict: verdict, rationale: "base: \(verdict)")
        }
    }

    private func context() -> SafetyContext {
        SafetyContext(
            mode: .auto,
            userMessage: "set up the tool",
            toolCall: ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"git clone https://x/y"}"#),
            toolDefinition: nil,
            recentMessages: []
        )
    }

    func testClarifyBecomesApprove() async {
        let reviewer = AutonomousApprovalSafetyReviewer(base: FixedReviewer(verdict: .clarify))
        let review = await reviewer.review(context())
        XCTAssertEqual(review.verdict, .approve)
        // Telemetry is honest about why it was approved.
        XCTAssertEqual(review.reviewTelemetry?.source, .autonomousOverride)
        // The base reviewer's reasoning is preserved for the audit trail.
        XCTAssertTrue(review.rationale.contains("base: clarify"))
    }

    func testDenyIsNeverConverted() async {
        let reviewer = AutonomousApprovalSafetyReviewer(base: FixedReviewer(verdict: .deny))
        let review = await reviewer.review(context())
        XCTAssertEqual(review.verdict, .deny, "hard-deny floors must still block in autonomous mode")
    }

    func testApproveIsPassedThroughUnchanged() async {
        let reviewer = AutonomousApprovalSafetyReviewer(base: FixedReviewer(verdict: .approve))
        let review = await reviewer.review(context())
        XCTAssertEqual(review.verdict, .approve)
        // An already-approved review is not re-stamped as an autonomous override.
        XCTAssertNotEqual(review.reviewTelemetry?.source, .autonomousOverride)
    }

    /// End-to-end with the real static policy: a hard-denied command stays denied even under the
    /// autonomous wrapper (defense-in-depth, not just the fixture).
    func testRealHardDenyStaysDeniedUnderAutonomousWrapper() async {
        let reviewer = AutonomousApprovalSafetyReviewer(base: StaticSafetyReviewer())
        let ctx = SafetyContext(
            mode: .auto,
            userMessage: "clean up",
            toolCall: ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"rm -rf /"}"#),
            toolDefinition: nil,
            recentMessages: []
        )
        let review = await reviewer.review(ctx)
        XCTAssertEqual(review.verdict, .deny)
    }
}
