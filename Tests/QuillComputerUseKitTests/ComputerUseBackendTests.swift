import XCTest
import QuillCodeCore
import QuillComputerUseKit

final class ComputerUseBackendTests: XCTestCase {
    func testPermissionStatusLabelsReadyState() {
        let status = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: true
        )

        XCTAssertTrue(status.available)
        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertTrue(status.accessibilityGranted)
        XCTAssertEqual(status.message, "Computer Use ready")
    }

    func testPermissionStatusLabelsMissingBothPermissions() {
        let status = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        )

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.message, "Needs Screen Recording + Accessibility")
    }

    func testPermissionStatusLabelsMissingScreenRecording() {
        let status = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: true
        )

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.message, "Needs Screen Recording")
    }

    func testPermissionStatusLabelsMissingAccessibility() {
        let status = ComputerUseStatus.permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: false
        )

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.message, "Needs Accessibility")
    }

    func testStubBackendRecordsActions() async throws {
        let backend = StubComputerUseBackend()

        _ = try await backend.screenshot()
        try await backend.leftClick(x: 10, y: 20)
        try await backend.type("hello")
        try await backend.scroll(dx: 1, dy: -2)
        try await backend.moveCursor(x: 30, y: 40)
        try await backend.pressKey("return")

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, [
            "screenshot",
            "leftClick:10,20",
            "type:hello",
            "scroll:1,-2",
            "move:30,40",
            "key:return"
        ])
    }

    func testComputerUseToolExecutorRoutesStructuredTools() async throws {
        let backend = StubComputerUseBackend()
        let artifactDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeComputerUseTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: artifactDirectory)
        }
        let executor = ComputerUseToolExecutor(
            backend: backend,
            artifactDirectory: artifactDirectory
        )

        let screenshotResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerScreenshot.name,
            argumentsJSON: "{}"
        ))
        let screenshot = try XCTUnwrap(screenshotResult)
        XCTAssertTrue(screenshot.ok)
        XCTAssertTrue(screenshot.stdout.contains(#""width" : 1"#))
        XCTAssertFalse(screenshot.stdout.contains("pngBase64"))
        let screenshotArtifact = try XCTUnwrap(screenshot.artifacts.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotArtifact))

        _ = await executor.execute(ToolCall(
            name: ToolDefinition.computerClick.name,
            argumentsJSON: #"{"x":10,"y":20}"#
        ))
        _ = await executor.execute(ToolCall(
            name: ToolDefinition.computerType.name,
            argumentsJSON: #"{"text":"hello"}"#
        ))
        _ = await executor.execute(ToolCall(
            name: ToolDefinition.computerScroll.name,
            argumentsJSON: #"{"dx":1,"dy":-2}"#
        ))
        _ = await executor.execute(ToolCall(
            name: ToolDefinition.computerMove.name,
            argumentsJSON: #"{"x":30,"y":40}"#
        ))
        _ = await executor.execute(ToolCall(
            name: ToolDefinition.computerKey.name,
            argumentsJSON: #"{"key":"return"}"#
        ))

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, [
            "screenshot",
            "leftClick:10,20",
            "type:hello",
            "scroll:1,-2",
            "move:30,40",
            "key:return"
        ])
    }

    func testComputerUseToolExecutorRejectsMissingCoordinates() async throws {
        let executor = ComputerUseToolExecutor(backend: StubComputerUseBackend())

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerClick.name,
            argumentsJSON: #"{"x":10}"#
        ))
        let result = try XCTUnwrap(toolResult)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Missing required integer argument: y")
    }

    func testMacBackendReportsCurrentPermissionState() {
        let status = MacComputerUseBackend().status

        XCTAssertEqual(status.available, status.screenRecordingGranted && status.accessibilityGranted)
        XCTAssertFalse(status.message.isEmpty)
    }
}
