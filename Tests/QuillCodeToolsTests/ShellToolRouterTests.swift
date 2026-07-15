import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class ShellToolRouterTests: XCTestCase {
    func testShellToolCallDispatcherOwnsShellDefinition() {
        let routerDefinitions = ToolRouter.definitions.map(\.name)
        let shellDefinitions = ShellToolCallDispatcher.definitions.map(\.name)

        XCTAssertTrue(ShellToolCallDispatcher.handles(ToolDefinition.shellRun.name))
        XCTAssertFalse(ShellToolCallDispatcher.handles(ToolDefinition.gitStatus.name))
        XCTAssertTrue(shellDefinitions.allSatisfy(routerDefinitions.contains))
    }

    func testToolRouterShellAllowsWorkspaceRelativeCWD() throws {
        let root = try makeTempDirectory()
        let subdirectory = root.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"basename \"$PWD\"","cwd":"subdir"}"#
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            subdirectory.lastPathComponent
        )
    }

    func testToolRouterShellRejectsCWDOutsideWorkspace() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"pwd","cwd":"\#(outside.path)"}"#
        ))

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Shell cwd must stay inside the current workspace.")
    }

    func testUnrestrictedToolRouterAllowsCWDOutsideWorkspace() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()

        let result = ToolRouter(
            workspaceRoot: root,
            accessScope: .unrestricted
        ).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"pwd","cwd":"\#(outside.path)"}"#
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        let actualPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let actualAttributes = try FileManager.default.attributesOfItem(atPath: actualPath)
        let expectedAttributes = try FileManager.default.attributesOfItem(atPath: outside.path)
        XCTAssertEqual(
            actualAttributes[.systemFileNumber] as? NSNumber,
            expectedAttributes[.systemFileNumber] as? NSNumber
        )
        XCTAssertEqual(
            actualAttributes[.systemNumber] as? NSNumber,
            expectedAttributes[.systemNumber] as? NSNumber
        )
    }

    func testToolRouterShellRejectsSymlinkCWDEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"pwd","cwd":"escape"}"#
        ))

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Shell cwd must stay inside the current workspace.")
    }

    func testToolRouterShellHonorsTimeoutSeconds() throws {
        let root = try makeTempDirectory()

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"sleep 2; echo should-not-print","timeoutSeconds":1}"#
        ))

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Command timed out after 1s.")
        XCTAssertFalse(result.stdout.contains("should-not-print"))
    }

    func testToolRouterShellRejectsUnsafeTimeoutSeconds() throws {
        let root = try makeTempDirectory()

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"pwd","timeout_seconds":1801}"#
        ))

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Shell timeoutSeconds must be between 1 and 1800.")
    }

    func testToolRouterShellUsesStructuredEnvironmentOverrides() throws {
        let root = try makeTempDirectory()

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"printf '%s' \"$QUILL_TOOL_ENV\"","environment":{"QUILL_TOOL_ENV":"from-tool"}}"#
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "from-tool")
    }

    func testToolRouterShellPassesStandardInput() throws {
        let root = try makeTempDirectory()

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"cat","stdin":"standard hook input\n"}"#
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "standard hook input\n")
    }

    func testToolRouterShellRejectsOversizedStandardInput() throws {
        let root = try makeTempDirectory()
        let input = String(repeating: "x", count: 1_048_577)
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "cat", "stdin": input])
        )

        let result = ToolRouter(workspaceRoot: root).execute(call)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Shell stdin must be at most 1048576 UTF-8 bytes.")
    }

    func testToolRouterShellRejectsUnsafeEnvironmentOverrides() throws {
        let root = try makeTempDirectory()

        let badKey = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"pwd","environment":{"BAD-KEY":"value"}}"#
        ))
        XCTAssertFalse(badKey.ok)
        XCTAssertEqual(
            badKey.error,
            "Shell environment keys must be ASCII identifiers up to 64 characters."
        )

        let badValue = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"pwd","environment":{"QUILL_ENV":"bad\nvalue"}}"#
        ))
        XCTAssertFalse(badValue.ok)
        XCTAssertEqual(
            badValue.error,
            "Shell environment values must be single-line strings up to 512 characters."
        )
    }
}
