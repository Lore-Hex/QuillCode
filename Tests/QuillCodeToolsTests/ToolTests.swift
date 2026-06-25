import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class ToolTests: XCTestCase {
    func testFileWriteStaysInsideWorkspace() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        let result = files.write(path: "nested/hello.txt", content: "hello world\n")
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(files.read(path: "nested/hello.txt").stdout, "hello world\n")
        XCTAssertFalse(files.write(path: "../escape.txt", content: "no").ok)
    }

    func testApplyPatchChangesWorkspaceFile() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("hello.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -hello
        +hello world
        """
        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello world\n")
    }

    func testApplyPatchRejectsUnsafePaths() throws {
        let root = try makeTempDirectory()
        let patch = """
        diff --git a/../escape.txt b/../escape.txt
        --- a/../escape.txt
        +++ b/../escape.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("unsafe path") == true, result.error ?? "")
    }

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
