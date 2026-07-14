import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ProjectRunHookOutputParserTests: XCTestCase {
    func testEmptyOutputContinuesWithoutContext() throws {
        let output = try ProjectRunHookOutputParser.parse(
            timing: .beforeAgentRun,
            result: ToolResult(ok: true, stdout: " \n")
        )

        XCTAssertEqual(output, ProjectRunHookSemanticOutput())
    }

    func testPlainUserPromptOutputBecomesBoundedContext() throws {
        let text = String(repeating: "x", count: ProjectRunHookOutputParser.maximumContextCharacters + 20)

        let output = try ProjectRunHookOutputParser.parse(
            timing: .beforeAgentRun,
            result: ToolResult(ok: true, stdout: text)
        )

        XCTAssertEqual(
            output.additionalContext?.count,
            ProjectRunHookOutputParser.maximumContextCharacters + 3
        )
        XCTAssertTrue(output.additionalContext?.hasSuffix("...") == true)
    }

    func testStructuredUserPromptOutputParsesCommonAndSpecificFields() throws {
        let output = try ProjectRunHookOutputParser.parse(
            timing: .beforeAgentRun,
            result: ToolResult(
                ok: true,
                stdout: #"{"continue":true,"systemMessage":"Policy loaded","suppressOutput":true,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Use the release branch."}}"#
            )
        )

        XCTAssertEqual(output.additionalContext, "Use the release branch.")
        XCTAssertEqual(output.systemMessage, "Policy loaded")
        XCTAssertTrue(output.continues)
        XCTAssertNil(output.blockReason)
    }

    func testContinueFalsePreservesBoundedStopReason() throws {
        let output = try ProjectRunHookOutputParser.parse(
            timing: .afterAgentRun,
            result: ToolResult(
                ok: true,
                stdout: #"{"continue":false,"stopReason":"Enough work for this run."}"#
            )
        )

        XCTAssertFalse(output.continues)
        XCTAssertEqual(output.stopReason, "Enough work for this run.")
    }

    func testBlockingDecisionRequiresReason() {
        XCTAssertThrowsError(try ProjectRunHookOutputParser.parse(
            timing: .beforeAgentRun,
            result: ToolResult(ok: true, stdout: #"{"decision":"block"}"#)
        )) { error in
            XCTAssertEqual(error as? ProjectRunHookOutputError, .missingBlockReason)
        }
    }

    func testExitTwoUsesStderrAsSemanticBlock() throws {
        let output = try ProjectRunHookOutputParser.parse(
            timing: .afterAgentRun,
            result: ToolResult(ok: false, stderr: "Run tests first.\n", exitCode: 2)
        )

        XCTAssertEqual(output.blockReason, "Run tests first.")
    }

    func testStopPlainTextIsRejected() {
        XCTAssertThrowsError(try ProjectRunHookOutputParser.parse(
            timing: .afterAgentRun,
            result: ToolResult(ok: true, stdout: "continue working")
        )) { error in
            XCTAssertEqual(error as? ProjectRunHookOutputError, .stopOutputMustBeJSON)
        }
    }

    func testKnownFieldsRejectWrongTypesAndMismatchedEvents() {
        XCTAssertThrowsError(try ProjectRunHookOutputParser.parse(
            timing: .beforeAgentRun,
            result: ToolResult(ok: true, stdout: #"{"continue":"yes"}"#)
        )) { error in
            XCTAssertEqual(error as? ProjectRunHookOutputError, .invalidType("continue"))
        }

        XCTAssertThrowsError(try ProjectRunHookOutputParser.parse(
            timing: .beforeAgentRun,
            result: ToolResult(
                ok: true,
                stdout: #"{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"wrong"}}"#
            )
        )) { error in
            XCTAssertEqual(error as? ProjectRunHookOutputError, .eventMismatch("Stop"))
        }
    }
}
