import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

final class OutsideWorkspaceShellCommandPreflightTests: XCTestCase {
    func testReportsOnlyUnauthorizedOutsideWorkspacePaths() throws {
        let root = URL(fileURLWithPath: "/workspace")
        let call = ToolCall(
            name: "host.shell.run",
            argumentsJSON: ToolArguments.json(["cmd": "cat inputs/data.csv > /tmp/data.txt"])
        )

        XCTAssertEqual(
            OutsideWorkspaceShellCommandPreflight.offendingPaths(
                in: call,
                userMessage: "Analyze inputs/data.csv.",
                workspaceRoot: root
            ),
            ["/tmp/data.txt"]
        )
        XCTAssertTrue(OutsideWorkspaceShellCommandPreflight.offendingPaths(
            in: call,
            userMessage: "Write the result to /tmp/data.txt",
            workspaceRoot: root
        ).isEmpty)
    }
}
