import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

final class SafetyShellPolicyTests: SafetyPolicyTestCase {
    func testAutoApprovesUserRequestedWhoami() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: shellRun.name, argumentsJSON: #"{"cmd":"whoami"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "whoami?",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "whoami?")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoModeHardDenyMatchesJSONUnicodeEscapedDangerousCommand() async {
        let reviewer = StaticSafetyReviewer()
        // The hard-deny must match the DECODED argument value, not the wire encoding. This drives the
        // matcher directly with a hand-built blob carrying a unicode-escaped slash (JSON u002f -> "/",
        // built from a runtime backslash so the source carries no literal escape). A raw-JSON match
        // misses it (would auto-approve under the "run" intent); the decode denies it. The live model
        // pipeline reserializes args before this check, so this guards the matcher's own correctness
        // against any future/partial path that carries raw model bytes.
        let backslash = String(UnicodeScalar(0x5C)!)
        let call = ToolCall(
            name: shellRun.name,
            argumentsJSON: "{\"cmd\":\"rm -rf \(backslash)u002f\"}"
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "run this for me",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "run this for me")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.deny, review.rationale)
    }

    func testAutoModeHardDenyMatchesJSONSlashEscapedDangerousCommand() async {
        let reviewer = StaticSafetyReviewer()
        // `\/` is the JSON escape for `/` that the prior one-off patch handled; the decode must keep
        // covering it (no regression).
        let call = ToolCall(name: shellRun.name, argumentsJSON: #"{"cmd":"rm -rf \/"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "run this for me",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "run this for me")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.deny, review.rationale)
    }

    func testAutoModeHardDenyStillMatchesPlainDangerousCommand() async {
        let reviewer = StaticSafetyReviewer()
        // Decoding must not weaken the common unescaped case.
        let call = ToolCall(name: shellRun.name, argumentsJSON: #"{"cmd":"rm -rf /"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "run this for me",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "run this for me")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.deny, review.rationale)
    }

    func testAutoModeHardDenyFallsBackToRawStringForMalformedJSON() async {
        let reviewer = StaticSafetyReviewer()
        // Not decodable JSON -> fall back to the raw blob so a dangerous pattern is still caught
        // (and nothing crashes).
        let call = ToolCall(name: shellRun.name, argumentsJSON: #"{"cmd": rm -rf / (not json"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "run this for me",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "run this for me")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.deny, review.rationale)
    }

    func testAutoApprovesDiagnosticShellRunWithoutRunVerb() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: shellRun.name,
            argumentsJSON: #"{"cmd":"command -v openclaw || which openclaw || echo 'not found'"}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "is openclaw installed?",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "is openclaw installed?")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesHdDiagnosticShellRunWithoutRunVerb() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: shellRun.name,
            argumentsJSON: #"{"cmd":"df -h / /Quill 2>/dev/null || df -h /"}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "How much hd?",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "How much hd?")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesReadOnlyListFilesShellRunWithoutRunVerb() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: shellRun.name, argumentsJSON: #"{"cmd":"ls -la"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "Can you list the files here?",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "Can you list the files here?")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesReadOnlyCurrentDirectoryShellRunWithoutRunVerb() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: shellRun.name, argumentsJSON: #"{"cmd":"pwd"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "Can you show me the current directory?",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "Can you show me the current directory?")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesReadOnlyGitStatusShellRunWithoutRunVerb() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: shellRun.name, argumentsJSON: #"{"cmd":"git status --short"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "Please check git status.",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "Please check git status.")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoDoesNotTreatReadOnlyShellIntentAsBlanketShellApproval() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: shellRun.name, argumentsJSON: #"{"cmd":"ls -la && cat ~/.ssh/id_rsa"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "Can you list the files here?",
            toolCall: call,
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: "Can you list the files here?")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.deny)
    }

}
