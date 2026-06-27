import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentPromisedWorkGuardTests: XCTestCase {
    func testDetectsFutureWorkPromise() {
        XCTAssertTrue(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I'll check your Quill's disk usage now.",
            tools: [.shellRun]
        ))
        XCTAssertTrue(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I will create the file.",
            tools: [.fileWrite]
        ))
    }

    func testDoesNotDetectCapabilityOrPermissionAnswers() {
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I can run commands, edit files, and review diffs when you ask.",
            tools: [.shellRun]
        ))
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "Do you want me to run the migration?",
            tools: [.shellRun]
        ))
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I will not run that command.",
            tools: [.shellRun]
        ))
    }

    func testDoesNotRequestCorrectionWithoutTools() {
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I'll run the command now.",
            tools: []
        ))
    }

    func testCorrectionPromptKeepsSchemaBoundaryExplicit() {
        let prompt = AgentPromisedWorkGuard.correctionPrompt(
            assistantText: "I'll run whoami.",
            userMessage: "whoami?"
        )

        XCTAssertTrue(prompt.contains("Return exactly one QuillCode JSON action"))
        XCTAssertTrue(prompt.contains(#"{"type":"tool",...}"#))
        XCTAssertTrue(prompt.contains(#"{"type":"say","text":"..."}"#))
        XCTAssertTrue(prompt.contains("whoami?"))
    }
}
