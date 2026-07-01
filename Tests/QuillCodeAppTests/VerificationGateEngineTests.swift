import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class VerificationGateEngineTests: XCTestCase {
    // MARK: - Verification-action detector (convention)

    private func action(id: String, title: String) -> LocalEnvironmentAction {
        LocalEnvironmentAction(id: id, title: title, relativePath: ".quillcode", command: "run")
    }

    func testDetectsByIdConvention() {
        let actions = [action(id: "build", title: "Build"), action(id: "test", title: "Run tests")]
        XCTAssertEqual(LocalEnvironmentActionMatcher.verificationAction(in: actions)?.id, "test")
    }

    func testDetectsByTitleConventionNormalized() {
        let actions = [action(id: "a1", title: "Verify ✅")]
        XCTAssertEqual(LocalEnvironmentActionMatcher.verificationAction(in: actions)?.id, "a1")
    }

    func testPrecedenceVerifyThenTestThenCheck() {
        let actions = [action(id: "check", title: "Check"), action(id: "test", title: "Test"), action(id: "verify", title: "Verify")]
        XCTAssertEqual(LocalEnvironmentActionMatcher.verificationAction(in: actions)?.id, "verify")
    }

    func testNoConventionalActionIsNil() {
        XCTAssertNil(LocalEnvironmentActionMatcher.verificationAction(in: [action(id: "deploy", title: "Ship it")]))
    }

    // MARK: - Edit detection

    private func toolThread(_ toolName: String) -> ChatThread {
        let call = ToolCall(name: toolName, argumentsJSON: ToolArguments.json(["x": "y"]))
        let payload = (try? JSONHelpers.encodePretty(call.redactedForTranscript())) ?? "{}"
        let event = ThreadEvent(kind: .toolQueued, summary: "\(toolName) queued", payloadJSON: payload)
        return ChatThread(title: "T", messages: [], events: [event])
    }

    func testThreadMadeEditsTrueForApplyPatchAndMutatingTools() {
        XCTAssertTrue(WorkspaceTurnRevertPlanner.threadMadeEdits(toolThread(ToolDefinition.applyPatch.name)))
        XCTAssertTrue(WorkspaceTurnRevertPlanner.threadMadeEdits(toolThread("host.shell.run")))
        XCTAssertTrue(WorkspaceTurnRevertPlanner.threadMadeEdits(toolThread("host.git.pr.checkout")))
    }

    func testThreadMadeEditsFalseForReadOnlyOrEmpty() {
        XCTAssertFalse(WorkspaceTurnRevertPlanner.threadMadeEdits(toolThread(ToolDefinition.fileRead.name)))
        XCTAssertFalse(WorkspaceTurnRevertPlanner.threadMadeEdits(ChatThread(title: "T", messages: [], events: [])))
    }

    // MARK: - Notification ladder

    private let threadID = UUID()

    private func plan(didEditFiles: Bool, hasVerificationAction: Bool = false, verification: VerificationVerdict? = nil, finalAnswer: String? = "Done.") -> AgentRunNotification? {
        AgentRunNotificationPlanner.notification(
            threadTitle: "Task",
            threadID: threadID,
            didFail: false,
            pendingApprovalSummary: nil,
            finalAnswer: finalAnswer,
            didEditFiles: didEditFiles,
            hasVerificationAction: hasVerificationAction,
            verification: verification
        )
    }

    func testVerifiedGreen() {
        let note = plan(didEditFiles: true, hasVerificationAction: true, verification: .passed)
        XCTAssertEqual(note?.kind, .verifiedGreen)
        XCTAssertEqual(note?.title, "QuillCode verified")
    }

    func testChecksFailingWithAndWithoutCount() {
        XCTAssertTrue(plan(didEditFiles: true, verification: .failed(count: 3))?.body.contains("3 checks failing") == true)
        XCTAssertTrue(plan(didEditFiles: true, verification: .failed(count: 1))?.body.contains("1 check failing") == true)
        XCTAssertTrue(plan(didEditFiles: true, verification: .failed(count: nil))?.body.contains("checks failing") == true)
        XCTAssertEqual(plan(didEditFiles: true, verification: .failed(count: 3))?.kind, .checksFailing)
    }

    func testTimedOutIsChecksFailing() {
        let note = plan(didEditFiles: true, verification: .timedOut)
        XCTAssertEqual(note?.kind, .checksFailing)
        XCTAssertTrue(note?.body.contains("timed out") == true)
    }

    func testUnverifiedOnlyWhenAVerifyActionExists() {
        // Edit + a verify action but no result yet -> honest "unverified".
        XCTAssertEqual(plan(didEditFiles: true, hasVerificationAction: true, verification: nil)?.kind, .unverified)
        // Edit but NO verify action -> unchanged plain finished (the user never opted in).
        XCTAssertEqual(plan(didEditFiles: true, hasVerificationAction: false, verification: nil)?.kind, .finished)
    }

    func testNonEditRunIsUnchangedFinished() {
        // Verification inputs are ignored for a run that changed nothing.
        XCTAssertEqual(plan(didEditFiles: false, hasVerificationAction: true, verification: .passed)?.kind, .finished)
    }

    func testDefaultsPreserveLegacyBehavior() {
        // The pre-gate call shape (no verification params) is byte-identical to before.
        let note = AgentRunNotificationPlanner.notification(
            threadTitle: "Task", threadID: threadID, didFail: false,
            pendingApprovalSummary: nil, finalAnswer: "Done."
        )
        XCTAssertEqual(note?.kind, .finished)
    }

    // MARK: - Builder (slice 1: no execution -> unverified for verify-action projects)

    func testBuilderReportsUnverifiedForEditRunWithVerifyAction() {
        let thread = toolThread(ToolDefinition.applyPatch.name)
        let note = WorkspaceRunNotificationBuilder.notification(
            thread: thread, didFail: false, localActions: [action(id: "test", title: "Test")]
        )
        XCTAssertEqual(note?.kind, .unverified)
    }

    func testBuilderUnchangedWhenNoVerifyAction() {
        let thread = toolThread(ToolDefinition.applyPatch.name)
        // Give the assistant a final answer so a plain finished notification is produced.
        var withAnswer = thread
        withAnswer.messages.append(ChatMessage(role: .assistant, content: "Done."))
        let note = WorkspaceRunNotificationBuilder.notification(thread: withAnswer, didFail: false, localActions: [])
        XCTAssertEqual(note?.kind, .finished)
    }
}
