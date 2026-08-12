import XCTest
@testable import QuillCodeAgent

final class AgentArtifactFinalityGateTests: XCTestCase {
    func testDetectsExplicitCheckpointHeadingAndStatus() {
        let content = """
        # CPI Revenue Restatement - Checkpoint Draft

        **Status:** Work in progress; source values are still being verified.
        """

        XCTAssertTrue(AgentArtifactFinalityGate.containsProvisionalCompletionLanguage(
            content: content,
            path: "outputs/report.md"
        ))
    }

    func testDoesNotRejectCompletedAnalysisThatDiscussesPendingItems() {
        let content = """
        # Final diligence report

        The source labels three customer renewals as pending. Next steps: Jo owns follow-up by Friday.
        """

        XCTAssertFalse(AgentArtifactFinalityGate.containsProvisionalCompletionLanguage(
            content: content,
            path: "outputs/report.md"
        ))
    }

    func testRecognizesExplicitRequestForProvisionalArtifact() {
        XCTAssertTrue(AgentArtifactFinalityGate.requestAllowsProvisionalArtifact(
            "Create an initial draft of the board memo at outputs/memo.md."
        ))
        XCTAssertFalse(AgentArtifactFinalityGate.requestAllowsProvisionalArtifact(
            "Draft exactly three complete emails and save them to outputs/emails.md."
        ))
    }
}
