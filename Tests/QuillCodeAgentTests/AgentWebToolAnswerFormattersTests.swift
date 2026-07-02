import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentWebToolAnswerFormattersTests: XCTestCase {
    private func call(_ urlJSON: String = #"{"url":"https://example.com/docs"}"#) -> ToolCall {
        ToolCall(name: ToolDefinition.webFetch.name, argumentsJSON: urlJSON)
    }

    func testFormatterIsRegistered() {
        // The formatter chain resolves a webFetch result without falling through to a generic answer.
        let result = ToolResult(ok: true, stdout: "Fetched https://example.com/docs (HTTP 200).\n\n# Title")
        let answers = AgentToolAnswerFormatters.all.compactMap { $0(call(), result, nil) }
        XCTAssertEqual(answers.count, 1)
        XCTAssertTrue(answers[0].contains("# Title"))
    }

    func testSuccessPassesContentThrough() {
        let result = ToolResult(ok: true, stdout: "Fetched https://example.com/docs.\n\n# Docs\n\nBody text")
        let answer = AgentWebToolAnswerFormatters.webFetchAnswer(call: call(), result: result, followUpReviewResult: nil)
        XCTAssertEqual(answer, "Fetched https://example.com/docs.\n\n# Docs\n\nBody text")
    }

    func testLongContentIsTruncatedForChat() {
        let result = ToolResult(ok: true, stdout: String(repeating: "m", count: 10_000))
        let answer = AgentWebToolAnswerFormatters.webFetchAnswer(call: call(), result: result, followUpReviewResult: nil)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer?.contains("[truncated in chat; full output is in the tool card]") == true)
        XCTAssertLessThan(answer?.count ?? .max, 3_000)
    }

    func testFailureExplainsWithError() {
        let result = ToolResult(ok: false, error: "Refused to fetch http://localhost/: loopback host.")
        let answer = AgentWebToolAnswerFormatters.webFetchAnswer(
            call: call(#"{"url":"http://localhost/"}"#),
            result: result,
            followUpReviewResult: nil
        )
        XCTAssertTrue(answer?.contains("Could not fetch http://localhost/") == true)
        XCTAssertTrue(answer?.contains("loopback host") == true)
    }

    func testFailureWithoutDetailsStillAnswers() {
        let result = ToolResult(ok: false)
        let answer = AgentWebToolAnswerFormatters.webFetchAnswer(call: call(), result: result, followUpReviewResult: nil)
        XCTAssertEqual(answer, "Could not fetch https://example.com/docs.")
    }

    func testOtherToolsAreIgnored() {
        let otherCall = ToolCall(name: ToolDefinition.fileRead.name, argumentsJSON: #"{"path":"a.txt"}"#)
        let result = ToolResult(ok: true, stdout: "x")
        XCTAssertNil(AgentWebToolAnswerFormatters.webFetchAnswer(call: otherCall, result: result, followUpReviewResult: nil))
    }

    func testEmptySuccessGetsPlaceholder() {
        let result = ToolResult(ok: true, stdout: "   \n  ")
        let answer = AgentWebToolAnswerFormatters.webFetchAnswer(call: call(), result: result, followUpReviewResult: nil)
        XCTAssertTrue(answer?.contains("no readable content") == true)
    }

    // MARK: - Web search formatter

    private func searchCall(_ json: String = #"{"query":"swift async"}"#) -> ToolCall {
        ToolCall(name: ToolDefinition.webSearch.name, argumentsJSON: json)
    }

    func testSearchFormatterIsRegistered() {
        let result = ToolResult(ok: true, stdout: "Search results for \"swift async\".\n\n1. Title\n   https://a.com")
        let answers = AgentToolAnswerFormatters.all.compactMap { $0(searchCall(), result, nil) }
        XCTAssertEqual(answers.count, 1)
        XCTAssertTrue(answers[0].contains("https://a.com"))
    }

    func testSearchSuccessPassesResultsThrough() {
        let result = ToolResult(ok: true, stdout: "Search results for \"swift async\".\n\n1. Title\n   https://a.com")
        let answer = AgentWebToolAnswerFormatters.webSearchAnswer(call: searchCall(), result: result, followUpReviewResult: nil)
        XCTAssertEqual(answer, "Search results for \"swift async\".\n\n1. Title\n   https://a.com")
    }

    func testSearchFailureExplainsWithError() {
        let result = ToolResult(ok: false, error: "Web search for \"x\" failed: upstream 503.")
        let answer = AgentWebToolAnswerFormatters.webSearchAnswer(call: searchCall(), result: result, followUpReviewResult: nil)
        XCTAssertTrue(answer?.contains("Could not search for swift async") == true)
        XCTAssertTrue(answer?.contains("upstream 503") == true)
    }

    func testSearchIgnoresOtherTools() {
        XCTAssertNil(AgentWebToolAnswerFormatters.webSearchAnswer(call: call(), result: ToolResult(ok: true, stdout: "x"), followUpReviewResult: nil))
    }
}
