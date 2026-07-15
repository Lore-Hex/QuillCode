import Foundation
@testable import QuillCodeCLI
import XCTest

final class CLIPromptResolverTests: XCTestCase {
    private let cwd = URL(fileURLWithPath: "/tmp")

    func testPromptArgumentIgnoresInteractiveTerminalInput() throws {
        let request = CLIRunRequest(style: .exec, prompt: "inspect", live: false, cwd: cwd)
        let resolved = try CLIPromptResolver().resolve(
            request: request,
            input: BufferedCLIInput(text: "should not be read", isTerminal: true)
        )
        XCTAssertEqual(resolved, "inspect")
    }

    func testPipedInputBecomesDelimitedUntrustedContext() throws {
        let request = CLIRunRequest(style: .exec, prompt: "summarize", live: false, cwd: cwd)
        let resolved = try CLIPromptResolver().resolve(
            request: request,
            input: BufferedCLIInput(text: "log output\n", isTerminal: false)
        )
        XCTAssertTrue(resolved.hasPrefix("summarize\n\n<cli_stdin_context>"))
        XCTAssertTrue(resolved.contains("untrusted context"))
        XCTAssertTrue(resolved.contains("log output"))
    }

    func testDashUsesStdinAsWholePrompt() throws {
        let request = CLIRunRequest(style: .exec, prompt: "-", live: false, cwd: cwd)
        XCTAssertEqual(
            try CLIPromptResolver().resolve(
                request: request,
                input: BufferedCLIInput(text: "  full prompt  ", isTerminal: true)
            ),
            "full prompt"
        )
    }

    func testMissingAndOversizedInputFail() {
        let request = CLIRunRequest(style: .exec, prompt: "-", live: false, cwd: cwd)
        XCTAssertThrowsError(try CLIPromptResolver().resolve(
            request: request,
            input: BufferedCLIInput(text: "", isTerminal: false)
        ))
        XCTAssertThrowsError(try CLIPromptResolver().resolve(
            request: request,
            input: BufferedCLIInput(
                data: Data(repeating: 65, count: CLIPromptResolver.maximumStdinBytes + 1)
            )
        ))
    }
}
