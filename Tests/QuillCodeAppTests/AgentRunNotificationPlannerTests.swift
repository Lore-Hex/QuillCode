import XCTest
@testable import QuillCodeApp

final class AgentRunNotificationPlannerTests: XCTestCase {
    private let threadID = UUID()

    func testApprovalGateTakesPriorityOverAnswer() {
        // Blocked on the user is the most urgent unattended signal — even if a partial answer exists.
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Refactor auth",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: "host.shell.run",
            finalAnswer: "I plan to run the migration."
        )
        XCTAssertEqual(note?.kind, .needsApproval)
        XCTAssertEqual(note?.title, "QuillCode needs your approval")
        XCTAssertTrue(note?.body.contains("Shell command") == true, note?.body ?? "")
        XCTAssertFalse(note?.body.contains("host.shell.run") == true, note?.body ?? "")
        XCTAssertTrue(note?.body.contains("Refactor auth") == true, note?.body ?? "")
        XCTAssertEqual(note?.threadID, threadID)
    }

    func testFailedRunNotifies() {
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Build the parser",
            threadID: threadID,
            didFail: true,
            pendingApprovalSummary: nil,
            finalAnswer: nil
        )
        XCTAssertEqual(note?.kind, .failed)
        XCTAssertTrue(note?.body.contains("Build the parser") == true, note?.body ?? "")
    }

    func testFinishedRunSummarizesTheAnswer() {
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Add tests",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: nil,
            finalAnswer: "Added 6 tests for the login flow.\nAll passing."
        )
        XCTAssertEqual(note?.kind, .finished)
        XCTAssertEqual(note?.title, "QuillCode finished")
        // Only the first line, and it carries the thread title as context.
        XCTAssertTrue(note?.body.contains("Added 6 tests for the login flow.") == true, note?.body ?? "")
        XCTAssertFalse(note?.body.contains("All passing.") == true, note?.body ?? "")
    }

    func testFinishedRunTruncatesLongAnswer() {
        let long = String(repeating: "x", count: 300)
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Task",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: nil,
            finalAnswer: long
        )
        XCTAssertEqual(note?.kind, .finished)
        XCTAssertTrue(note?.body.hasSuffix("…") == true, note?.body ?? "")
        XCTAssertLessThan(note?.body.count ?? .max, 140)
    }

    func testNothingToNotifyReturnsNil() {
        // No answer, no failure, no approval (e.g. a cancelled or empty run) — do not interrupt.
        XCTAssertNil(AgentRunNotificationPlanner.notification(
            threadTitle: "Task",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: nil,
            finalAnswer: "   "
        ))
    }

    func testEmptyThreadTitleFallsBack() {
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "   ",
            threadID: threadID,
            didFail: true,
            pendingApprovalSummary: nil,
            finalAnswer: nil
        )
        XCTAssertTrue(note?.body.contains("Your task") == true, note?.body ?? "")
    }

    // MARK: - Run-integrity badge (#875)

    func testVerifiedBadgeIsRecordedButDoesNotShoutInTitle() {
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Add tests",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: nil,
            finalAnswer: "Added 6 tests.",
            integrity: .verified
        )
        XCTAssertEqual(note?.integrity, .verified)
        // A clean run does not need a loud badge in the title.
        XCTAssertEqual(note?.title, "QuillCode finished")
    }

    func testUnverifiedBadgeStampsTheTitle() {
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Add tests",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: nil,
            finalAnswer: "Added 6 tests; tests pass.",
            integrity: .unverified
        )
        XCTAssertEqual(note?.integrity, .unverified)
        XCTAssertTrue(note?.title.hasPrefix("[UNVERIFIED]") == true, note?.title ?? "")
    }

    func testRedBadgeStampsTheTitle() {
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Fix parser",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: nil,
            finalAnswer: "Pushed.",
            integrity: .red
        )
        XCTAssertEqual(note?.integrity, .red)
        XCTAssertTrue(note?.title.hasPrefix("[RED]") == true, note?.title ?? "")
    }

    func testRedBadgeSurfacesEvenWithNoFinalAnswer() {
        // A silent RED run (no assistant answer text) must still notify with the badge.
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Fix parser",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: nil,
            finalAnswer: nil,
            integrity: .red
        )
        XCTAssertEqual(note?.integrity, .red)
        XCTAssertTrue(note?.title.hasPrefix("[RED]") == true, note?.title ?? "")
    }

    func testBadgeDoesNotOverrideApprovalGate() {
        // The approval gate is more urgent than the honesty stamp — it must win and stay unstamped.
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Task",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: "host.shell.run",
            finalAnswer: nil,
            integrity: .red
        )
        XCTAssertEqual(note?.kind, .needsApproval)
        XCTAssertEqual(note?.title, "QuillCode needs your approval")
    }
}
