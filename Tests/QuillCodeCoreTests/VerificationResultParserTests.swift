import XCTest
@testable import QuillCodeCore

final class VerificationResultParserTests: XCTestCase {
    private func result(ok: Bool, exitCode: Int32? = nil, stdout: String = "", stderr: String = "") -> ToolResult {
        ToolResult(ok: ok, stdout: stdout, stderr: stderr, exitCode: exitCode, error: nil)
    }

    func testExitZeroPasses() {
        XCTAssertEqual(VerificationResultParser.parse(result(ok: true, exitCode: 0, stdout: "All tests passed")), .passed)
    }

    func testExit127IsCommandNotFound() {
        XCTAssertEqual(VerificationResultParser.parse(result(ok: false, exitCode: 127, stderr: "swiftt: command not found")), .commandNotFound)
    }

    func testFailingWithParsedCount() {
        XCTAssertEqual(VerificationResultParser.parse(result(ok: false, exitCode: 1, stdout: "3 failed, 42 passed")), .failed(count: 3))
        XCTAssertEqual(VerificationResultParser.parse(result(ok: false, exitCode: 1, stdout: "Tests: 2 failing")), .failed(count: 2))
        XCTAssertEqual(VerificationResultParser.parse(result(ok: false, exitCode: 1, stderr: "FAILED (failures=5)")), .failed(count: 5))
        XCTAssertEqual(VerificationResultParser.parse(result(ok: false, exitCode: 1, stdout: "1 test failed")), .failed(count: 1))
        // Swift/XCTest output shape — the primary one for QuillCode projects.
        XCTAssertEqual(VerificationResultParser.parse(result(ok: false, exitCode: 1, stdout: "Executed 100 tests, with 3 failures (0 unexpected)")), .failed(count: 3))
    }

    func testFailingWithoutParseableCount() {
        // No recognizable number -> nil (never fabricate a count).
        XCTAssertEqual(VerificationResultParser.parse(result(ok: false, exitCode: 2, stderr: "build failed: linker error")), .failed(count: nil))
    }

    func testZeroFailuresIsNotTreatedAsACount() {
        // "0 failed" must not surface as ".failed(count: 0)".
        XCTAssertEqual(VerificationResultParser.parse(result(ok: false, exitCode: 1, stdout: "0 failed but the runner crashed")), .failed(count: nil))
    }
}
