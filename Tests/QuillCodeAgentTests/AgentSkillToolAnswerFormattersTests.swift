import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentSkillToolAnswerFormattersTests: XCTestCase {
    private func call(_ json: String = #"{"name":"code-review"}"#) -> ToolCall {
        ToolCall(name: ToolDefinition.skillLoad.name, argumentsJSON: json)
    }

    func testFormatterIsRegistered() {
        // The formatter chain resolves a skillLoad result without falling through to a generic answer.
        let result = ToolResult(ok: true, stdout: "Loaded user skill `code-review`.\n\n<skill_content>…</skill_content>")
        let answers = AgentToolAnswerFormatters.all.compactMap { $0(call(), result, nil) }
        XCTAssertEqual(answers.count, 1)
        XCTAssertTrue(answers[0].contains("skill_content"))
    }

    func testSuccessPassesContentThrough() {
        let result = ToolResult(ok: true, stdout: "Loaded builtin skill `code-review`.\n\n<skill_content>body</skill_content>")
        let answer = AgentSkillToolAnswerFormatters.skillLoadAnswer(call: call(), result: result, followUpReviewResult: nil)
        XCTAssertEqual(answer, "Loaded builtin skill `code-review`.\n\n<skill_content>body</skill_content>")
    }

    func testFailureExplainsWithError() {
        let result = ToolResult(ok: false, error: "No skill named `code-reviw`. Did you mean `code-review`?")
        let answer = AgentSkillToolAnswerFormatters.skillLoadAnswer(
            call: call(#"{"name":"code-reviw"}"#),
            result: result,
            followUpReviewResult: nil
        )
        XCTAssertTrue(answer?.contains("Could not load skill `code-reviw`") == true, answer ?? "")
        XCTAssertTrue(answer?.contains("Did you mean `code-review`?") == true, answer ?? "")
    }

    func testFailureWithoutDetailsStillAnswers() {
        let result = ToolResult(ok: false)
        let answer = AgentSkillToolAnswerFormatters.skillLoadAnswer(call: call(), result: result, followUpReviewResult: nil)
        XCTAssertEqual(answer, "Could not load skill `code-review`.")
    }

    func testOtherToolsAreIgnored() {
        let otherCall = ToolCall(name: ToolDefinition.fileRead.name, argumentsJSON: #"{"path":"a.txt"}"#)
        let result = ToolResult(ok: true, stdout: "x")
        XCTAssertNil(AgentSkillToolAnswerFormatters.skillLoadAnswer(call: otherCall, result: result, followUpReviewResult: nil))
    }
}
