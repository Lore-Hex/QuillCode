import XCTest
@testable import QuillCodeCore

/// Tests for the per-thread return digest (issue #877): verdict + reasons + final outcome + unseen seam.
final class TriageDigestTests: XCTestCase {

    private func threadWithRedRun(unseenAnswer: String = "Done. Left a failing test.") -> ChatThread {
        var thread = ChatThread(title: "fix the parser")
        // A real standing failure the scanner will flag RED.
        let call = ToolCall(
            name: RunIntegrityScanner.shellRunToolName,
            argumentsJSON: #"{"cmd":"make test"}"#
        )
        let failResult = ToolResult(ok: false, stdout: "", stderr: "1 failing", exitCode: 1, error: nil)
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? "{}"
        let resultJSON = (try? JSONHelpers.encodePretty(failResult)) ?? "{}"
        thread.events.append(ThreadEvent(kind: .toolQueued, summary: "\(call.name) queued", payloadJSON: callJSON))
        thread.events.append(ThreadEvent(kind: .toolRunning, summary: "\(call.name) running"))
        thread.events.append(ThreadEvent(kind: .toolFailed, summary: "\(call.name) failed", payloadJSON: resultJSON))
        thread.messages.append(ChatMessage(role: .user, content: "fix it"))
        thread.messages.append(ChatMessage(role: .assistant, content: unseenAnswer))
        // Persist the integrity record the way the app does.
        RunIntegrityRecord.record(into: &thread)
        return thread
    }

    func testDigestCarriesVerdictReasonsOutcomeAndSeam() {
        let thread = threadWithRedRun()
        let digest = TriageDigest.build(for: thread, unseenCount: 2)
        XCTAssertEqual(digest.verdict, .red)
        XCTAssertFalse(digest.verdictSummary.isEmpty)
        XCTAssertFalse(digest.reasons.isEmpty, "a RED run must expose its reasons in the card body")
        XCTAssertEqual(digest.outcome, "Done. Left a failing test.")
        XCTAssertEqual(digest.unseenCount, 2)
        XCTAssertEqual(digest.unseenSeamLabel, "2 unseen turns")
    }

    func testDigestSingularSeamLabel() {
        let digest = TriageDigest.build(for: threadWithRedRun(), unseenCount: 1)
        XCTAssertEqual(digest.unseenSeamLabel, "1 unseen turn")
    }

    func testDigestNoUnseenHasNoSeamLabel() {
        let digest = TriageDigest.build(for: threadWithRedRun(), unseenCount: 0)
        XCTAssertNil(digest.unseenSeamLabel)
    }

    func testDigestNeverNegativeUnseen() {
        let digest = TriageDigest.build(for: threadWithRedRun(), unseenCount: -5)
        XCTAssertEqual(digest.unseenCount, 0)
    }

    func testDigestForUnscannedThreadHasNoVerdictOrReasons() {
        var thread = ChatThread(title: "just chatting")
        thread.messages.append(ChatMessage(role: .assistant, content: "hi there"))
        let digest = TriageDigest.build(for: thread, unseenCount: 0)
        XCTAssertNil(digest.verdict)
        XCTAssertTrue(digest.verdictSummary.isEmpty)
        XCTAssertTrue(digest.reasons.isEmpty)
        XCTAssertEqual(digest.outcome, "hi there")
    }

    func testDigestOutcomeFallsBackWhenNoAssistantMessage() {
        var thread = ChatThread(title: "empty")
        thread.messages.append(ChatMessage(role: .user, content: "hello?"))
        let digest = TriageDigest.build(for: thread, unseenCount: 0)
        XCTAssertEqual(digest.outcome, "No final answer recorded.")
    }

    func testOutcomeLineTakesFirstNonEmptyLineAndTruncates() {
        let long = String(repeating: "x", count: 200)
        let text = "\n\n  \(long)\nsecond line"
        let line = TriageDigest.firstLine(of: text, maxLength: 140)
        XCTAssertTrue(line.hasSuffix("…"))
        XCTAssertLessThanOrEqual(line.count, 141)
    }
}
