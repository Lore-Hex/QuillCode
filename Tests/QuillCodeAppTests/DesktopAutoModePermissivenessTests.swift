import XCTest
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

/// The desktop's daily-driver contract: in auto mode a benign setup step must NOT stop the task
/// behind an approval, while the hard floors and the out-of-workspace shell guard still hold.
///
/// Live failure this encodes: an office task ("pull the transaction tables out of these PDFs …")
/// stalled on `python3 -c "import sys; print(sys.version)"` with the rationale "The requested tool
/// action does not clearly match the latest user message."
final class DesktopAutoModePermissivenessTests: XCTestCase {
    private func context(cmd: String, userMessage: String) -> SafetyContext {
        SafetyContext(
            mode: .auto,
            userMessage: userMessage,
            toolCall: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": cmd])
            ),
            toolDefinition: .shellRun,
            recentMessages: [],
            workspaceRoot: URL(fileURLWithPath: "/tmp/ws")
        )
    }

    private let officeTask = "Pull the transaction tables out of these three bank statement PDFs into one clean CSV with date, description, and amount. Save it as transactions.csv"

    func testStaticPolicyAloneWouldStallABenignSetupStep() async {
        let review = await AutoSafetyReviewer().review(
            context(cmd: "python3 -c \"import sys; print(sys.version)\"", userMessage: officeTask)
        )
        XCTAssertEqual(review.verdict, .clarify, "baseline: this is the stall the desktop showed")
    }

    func testDesktopWrapperApprovesBenignSetupSteps() async {
        let reviewer = AutonomousApprovalSafetyReviewer(base: AutoSafetyReviewer())
        for cmd in [
            "python3 -c \"import sys; print(sys.version)\"",
            "command -v pdftotext",
            "pdftotext -layout statement-2026-04.pdf -",
            "python3 -m venv .venv && .venv/bin/pip install pypdf",
        ] {
            let review = await reviewer.review(context(cmd: cmd, userMessage: officeTask))
            XCTAssertEqual(review.verdict, .approve, "auto mode must not stall on: \(cmd)")
        }
    }

    func testOutsideWorkspaceShellIsStillBlocked() async {
        let reviewer = AutonomousApprovalSafetyReviewer(base: AutoSafetyReviewer())
        let review = await reviewer.review(
            context(cmd: "grep -r secret ~/Documents", userMessage: officeTask)
        )
        XCTAssertEqual(review.verdict, .deny, "F24: out-of-workspace reads still require a human")
    }
}
