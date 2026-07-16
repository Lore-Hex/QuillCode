import XCTest
import QuillCodeCore
@testable import QuillCodeTools

// MARK: - Unit: the pure capper

final class ShellOutputCapperTests: XCTestCase {
    func testUnderLimitPassesThroughUnchanged() {
        let text = "a\nb\nc"
        let result = ShellOutputCapper.cap(text, maxLines: 100, maxBytes: 10_000)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.text, text)
    }

    func testOverLineLimitKeepsTheTail() {
        let text = (1...3000).map { "line\($0)" }.joined(separator: "\n")
        let result = ShellOutputCapper.cap(text, maxLines: 100, maxBytes: 1_000_000)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.text.contains("output truncated"))
        XCTAssertTrue(result.text.contains("line3000"), "the tail must be kept")     // last line
        XCTAssertFalse(result.text.contains("line1\n"), "early lines must be dropped")
        // note line + 100 kept lines
        XCTAssertLessThanOrEqual(result.text.components(separatedBy: "\n").count, 102)
    }

    func testOverByteLimitTruncates() {
        let text = String(repeating: "x", count: 200_000)
        let result = ShellOutputCapper.cap(text, maxLines: 1_000_000, maxBytes: 1000)
        XCTAssertTrue(result.truncated)
        XCTAssertLessThan(result.text.utf8.count, 2000)
    }

    func testEmptyIsPassthrough() {
        XCTAssertFalse(ShellOutputCapper.cap("").truncated)
    }

    func testExactlyMaxLinesWithTrailingNewlineIsNotTruncated() {
        // 100 lines ending in a newline IS 100 lines (wc -l semantics) — the trailing newline must not
        // count as a 101st empty line and trip the cap one line early.
        let text = (1...100).map { "line\($0)\n" }.joined()
        let result = ShellOutputCapper.cap(text, maxLines: 100, maxBytes: 1_000_000)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.text, text)
    }

    func testNoteReportsWcStyleLineCount() {
        let text = (1...150).map { "line\($0)\n" }.joined()
        let result = ShellOutputCapper.cap(text, maxLines: 100, maxBytes: 1_000_000)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.text.contains("150 lines"), "must report 150, not 151: \(result.text.prefix(80))")
    }

    func testByteCutLandsOnCodepointBoundaryNoReplacementChars() {
        // 34 '€' (3 bytes each = 102 bytes) cut at 50 bytes lands mid-scalar; the cut must back off to
        // a codepoint boundary instead of decoding dangling continuation bytes to U+FFFD garbage.
        let text = String(repeating: "\u{20AC}", count: 34)
        let result = ShellOutputCapper.cap(text, maxLines: 2000, maxBytes: 50)
        XCTAssertTrue(result.truncated)
        XCTAssertFalse(result.text.contains("\u{FFFD}"), "no replacement characters allowed")
        XCTAssertTrue(result.text.hasSuffix("\u{20AC}"), "the tail should still be euro signs")
    }

    func testByteCutInsideFourByteScalarDropsItCleanly() {
        // suffix(3) of a 4-byte emoji is pure continuation bytes — they must be dropped, not decoded.
        let result = ShellOutputCapper.cap("a\u{1F600}", maxLines: 10, maxBytes: 3)
        XCTAssertTrue(result.truncated)
        XCTAssertFalse(result.text.contains("\u{FFFD}"))
    }

    func testAccumulatorBoundsAcrossChunksAndReportsCompleteCounts() {
        var accumulator = ShellOutputAccumulator(maxLines: 3, maxBytes: 1_000)
        accumulator.append("line1\nline2\n")
        accumulator.append("line3\nline4\n")

        XCTAssertTrue(accumulator.text.contains("4 lines, 24 bytes total"), accumulator.text)
        XCTAssertFalse(accumulator.text.contains("line1\n"), accumulator.text)
        XCTAssertTrue(accumulator.text.hasSuffix("line2\nline3\nline4\n"), accumulator.text)
    }

    func testAccumulatorKeepsValidUTF8TailAcrossByteBoundary() {
        var accumulator = ShellOutputAccumulator(maxLines: 100, maxBytes: 5)
        accumulator.append("prefix")
        accumulator.append("\u{1F600}\u{1F680}")

        XCTAssertTrue(accumulator.text.contains("14 bytes total"), accumulator.text)
        XCTAssertFalse(accumulator.text.contains("\u{FFFD}"), accumulator.text)
        XCTAssertTrue(accumulator.text.hasSuffix("\u{1F680}"), accumulator.text)
    }
}

// MARK: - Functional: through the shell executor with real output

final class ShellToolExecutorCapFunctionalTests: XCTestCase {
    func testExecutorCapsAChattyCommand() {
        let request = ShellExecutionRequest(
            command: "seq 5000",
            cwd: FileManager.default.temporaryDirectory,
            timeoutSeconds: 30
        )
        let result = ShellToolExecutor().run(request)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("output truncated"), "5000 lines should be capped")
        XCTAssertTrue(result.stdout.contains("\n5000"), "the tail (final lines) must survive")
        XCTAssertLessThan(result.stdout.components(separatedBy: "\n").count, 2100, "capped near the 2000-line ceiling")
    }

    func testStreamingExecutorCapsAChattyCommand() async throws {
        let stream = ShellToolExecutor().runStreaming(.init(
            command: "seq 5000",
            cwd: FileManager.default.temporaryDirectory,
            timeoutSeconds: 30
        ))
        var finishedResult: ToolResult?
        for await event in stream {
            if case .finished(let result) = event { finishedResult = result }
        }

        let result = try XCTUnwrap(finishedResult)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("output truncated"))
        XCTAssertTrue(result.stdout.contains("\n5000"))
        XCTAssertLessThan(result.stdout.utf8.count, 60_000)
    }
}

// MARK: - Integration: through the ToolRouter dispatch the agent uses

final class ShellToolOutputCapIntegrationTests: XCTestCase {
    func testRouterDispatchedShellRunIsCapped() {
        let router = ToolRouter(workspaceRoot: FileManager.default.temporaryDirectory)
        let call = ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"seq 5000"}"#)
        let result = router.execute(call)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("output truncated"))
        XCTAssertTrue(result.stdout.contains("\n5000"))
    }
}
