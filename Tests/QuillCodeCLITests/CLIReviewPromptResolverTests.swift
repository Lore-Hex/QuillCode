import Foundation
@testable import QuillCodeCLI
import QuillCodeReview
import XCTest

final class CLIReviewPromptResolverTests: XCTestCase {
    private let cwd = URL(fileURLWithPath: "/tmp/project")
    private let resolver = CLIReviewPromptResolver()

    func testCustomArgumentIsUsedWithoutReadingTerminalInput() throws {
        let resolved = try resolver.resolve(
            request: request(target: .custom("Focus on cancellation")),
            input: BufferedCLIInput(text: "ignored", isTerminal: true)
        )

        XCTAssertEqual(resolved.scope, .custom)
        XCTAssertEqual(resolved.instructions, "Focus on cancellation")
    }

    func testDashReadsTrimmedStdinAsCustomInstructions() throws {
        let resolved = try resolver.resolve(
            request: request(target: .custom("-")),
            input: BufferedCLIInput(text: "  Focus on actor isolation.\n", isTerminal: false)
        )

        XCTAssertEqual(resolved.scope, .custom)
        XCTAssertEqual(resolved.instructions, "Focus on actor isolation.")
    }

    func testTargetFlagNeverConsumesUnrelatedPipedInput() throws {
        let resolved = try resolver.resolve(
            request: request(target: .uncommitted),
            input: BufferedCLIInput(text: "untrusted piped text", isTerminal: false)
        )

        XCTAssertEqual(resolved.scope, .uncommitted)
        XCTAssertNil(resolved.instructions)
    }

    func testDashRejectsEmptyInvalidAndOversizedInput() {
        let dash = request(target: .custom("-"))
        assertCLIError(.missingPrompt) {
            _ = try resolver.resolve(
                request: dash,
                input: BufferedCLIInput(text: " \n", isTerminal: false)
            )
        }
        assertCLIError(.invalidUTF8Stdin) {
            _ = try resolver.resolve(
                request: dash,
                input: BufferedCLIInput(data: Data([0xFF]), isTerminal: false)
            )
        }
        assertCLIError(.stdinTooLarge(limit: CLIStdinTextReader.maximumBytes)) {
            _ = try resolver.resolve(
                request: dash,
                input: BufferedCLIInput(
                    data: Data(repeating: 65, count: CLIStdinTextReader.maximumBytes + 1),
                    isTerminal: false
                )
            )
        }
    }

    private func request(target: CLIReviewTarget) -> CLIReviewRequest {
        CLIReviewRequest(target: target, live: false, cwd: cwd)
    }

    private func assertCLIError(
        _ expected: CLIError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? CLIError, expected, file: file, line: line)
        }
    }
}
