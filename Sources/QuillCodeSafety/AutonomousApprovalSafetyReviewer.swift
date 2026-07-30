import Foundation
import QuillCodeCore

/// Delivers the autonomous behavior a headless `--sandbox workspace-write` run is supposed to have
/// (it is the flag that REPLACED `--full-auto`): a base reviewer's `.clarify` verdict — "I'm not
/// sure this matches the request; ask the human" — becomes `.approve`, because in a headless run
/// there is no human to ask.
///
/// Without this, an unattended run dead-ends on the first command the static policy does not
/// recognize and the model reviewer is unsure about — a plain `git clone …` or `uv venv …` during
/// task setup stalls the entire run at `approval_required`, which is exactly what broke coworker
/// use case #1 (BFCL from scratch) after the deferral-stall fix let it get that far.
///
/// Safety boundary is unchanged: this NEVER converts `.deny`. The hard-deny floors (rm -rf,
/// pipe-to-shell, sudo, system-path writes, secret reads) still block, and the workspace-write
/// sandbox still confines filesystem writes. This only removes the "ask a human" step that has no
/// answer in an autonomous run — it does not remove the "never do this" rules.
///
/// Applied ONLY to headless/exec runs whose sandbox is workspace-write or danger-full-access.
/// Interactive runs keep their `.clarify` so the human at the keyboard can decide.
public struct AutonomousApprovalSafetyReviewer: SafetyReviewer {
    private let base: any SafetyReviewer

    public init(base: any SafetyReviewer) {
        self.base = base
    }

    public func review(_ context: SafetyContext) async -> SafetyReview {
        let review = await base.review(context)
        guard review.verdict == .clarify else { return review }

        return SafetyReview(
            verdict: .approve,
            rationale: "Autonomous run: proceeding without a human approval step. "
                + "Hard-deny rules and the workspace sandbox still apply. "
                + "(Base reviewer said: \(review.rationale))",
            reviewerModel: review.reviewerModel,
            userIntentMatched: review.userIntentMatched,
            riskLevel: review.riskLevel,
            userAuthorization: review.userAuthorization
        ).withReviewTelemetry(.init(source: .autonomousOverride))
    }
}
