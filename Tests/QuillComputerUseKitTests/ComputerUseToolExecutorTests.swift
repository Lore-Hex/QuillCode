import XCTest
import QuillCodeCore
import QuillComputerUseKit

final class ComputerUseToolExecutorTests: XCTestCase {
    func testStubBackendRecordsActions() async throws {
        let backend = StubComputerUseBackend()

        _ = try await backend.screenshot()
        try await backend.leftClick(x: 10, y: 20)
        try await backend.type("hello")
        try await backend.scroll(dx: 1, dy: -2)
        try await backend.moveCursor(x: 30, y: 40)
        try await backend.pressKey("return")

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, expectedRecordedActions())
    }

    func testComputerUseToolExecutorRoutesStructuredTools() async throws {
        let backend = StubComputerUseBackend()
        let executor = ComputerUseToolExecutor(
            backend: backend,
            artifactDirectory: temporaryArtifactDirectory()
        )

        let screenshot = try await assertScreenshotSucceeds(executor)
        XCTAssertTrue(screenshot.stdout.contains(#""width" : 1"#))
        XCTAssertFalse(screenshot.stdout.contains("pngBase64"))

        await executeStandardInputActions(with: executor)
        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, expectedRecordedActions())
    }

    func testScreenshotOutputIncludesForegroundApplicationWhenAvailable() async throws {
        let backend = StubComputerUseBackend(foregroundApplication: ComputerUseApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        ))
        let executor = ComputerUseToolExecutor(
            backend: backend,
            artifactDirectory: temporaryArtifactDirectory()
        )

        let result = try await assertScreenshotSucceeds(executor)
        let output = try JSONHelpers.decode(ComputerScreenshotToolOutput.self, from: result.stdout)

        XCTAssertEqual(output.width, 1)
        XCTAssertEqual(output.height, 1)
        XCTAssertEqual(output.foregroundApplication?.name, "Terminal")
        XCTAssertEqual(output.foregroundApplication?.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(
            output.visualSummary,
            "Captured 1 x 1 desktop screenshot; foreground app: Terminal; preview artifact: \(URL(fileURLWithPath: try XCTUnwrap(output.path)).lastPathComponent)"
        )
        XCTAssertFalse(result.stdout.contains("pngBase64"))
    }

    func testAppApprovalAllowsApprovedForegroundBundle() async throws {
        let backend = StubComputerUseBackend(foregroundApplication: ComputerUseApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        ))
        let executor = ComputerUseToolExecutor(
            backend: backend,
            appApprovalPolicy: ComputerUseAppApprovalPolicy(
                approvedBundleIdentifiers: [" com.apple.terminal "]
            )
        )

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerClick.name,
            argumentsJSON: #"{"x":10,"y":20}"#
        ))
        let result = try XCTUnwrap(toolResult)
        let actions = await backend.recordedActions()

        XCTAssertTrue(result.ok)
        XCTAssertEqual(actions, ["leftClick:10,20"])
    }

    func testAppApprovalAllowsApprovedForegroundName() async throws {
        let backend = StubComputerUseBackend(foregroundApplication: ComputerUseApplication(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        ))
        let executor = ComputerUseToolExecutor(
            backend: backend,
            appApprovalPolicy: ComputerUseAppApprovalPolicy(approvedAppNames: ["google chrome"])
        )

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerKey.name,
            argumentsJSON: #"{"key":"return"}"#
        ))
        let result = try XCTUnwrap(toolResult)
        let actions = await backend.recordedActions()

        XCTAssertTrue(result.ok)
        XCTAssertEqual(actions, ["key:return"])
    }

    func testAppApprovalBlocksUnapprovedForegroundApp() async throws {
        let backend = StubComputerUseBackend(foregroundApplication: ComputerUseApplication(
            name: "Passwords",
            bundleIdentifier: "com.apple.Passwords"
        ))
        let executor = ComputerUseToolExecutor(
            backend: backend,
            appApprovalPolicy: ComputerUseAppApprovalPolicy(
                approvedBundleIdentifiers: ["com.apple.Terminal"]
            )
        )

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerType.name,
            argumentsJSON: #"{"text":"secret"}"#
        ))
        let result = try XCTUnwrap(toolResult)
        let actions = await backend.recordedActions()

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Computer Use is not approved for Passwords. Add this app to Computer Use approvals before controlling it."
        )
        XCTAssertEqual(actions, [])
    }

    func testAppApprovalRequiresForegroundAppProviderWhenConfigured() async throws {
        let backend = PermissionRecordingComputerUseBackend(
            status: .permissionStatus(screenRecordingGranted: true, accessibilityGranted: true)
        )
        let executor = ComputerUseToolExecutor(
            backend: backend,
            appApprovalPolicy: ComputerUseAppApprovalPolicy(approvedAppNames: ["Terminal"])
        )

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerScroll.name,
            argumentsJSON: #"{"dy":120}"#
        ))
        let result = try XCTUnwrap(toolResult)
        let actions = await backend.recordedActions()

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Computer Use scroll needs app approval, but this backend cannot identify the focused application."
        )
        XCTAssertEqual(actions, [])
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

    func testComputerUseToolExecutorPreflightsScreenRecordingForScreenshots() async throws {
        let backend = PermissionRecordingComputerUseBackend(
            status: .permissionStatus(
                screenRecordingGranted: false,
                accessibilityGranted: true
            )
        )
        let executor = ComputerUseToolExecutor(backend: backend)

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerScreenshot.name,
            argumentsJSON: "{}"
        ))
        let result = try XCTUnwrap(toolResult)
        let actions = await backend.recordedActions()

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Computer Use screenshot needs Screen Recording. Open Computer Use setup from Settings, grant Screen Recording, then refresh status."
        )
        XCTAssertEqual(actions, [])
    }

    func testComputerUseToolExecutorPreflightsAccessibilityForInputActions() async throws {
        let backend = PermissionRecordingComputerUseBackend(
            status: .permissionStatus(
                screenRecordingGranted: true,
                accessibilityGranted: false
            )
        )
        let executor = ComputerUseToolExecutor(backend: backend)

        for caseUnderTest in accessibilityPreflightCases() {
            let toolResult = await executor.execute(caseUnderTest.call)
            let result = try XCTUnwrap(toolResult)
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, caseUnderTest.expectedError)
        }
        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, [])
    }

    func testComputerUseToolExecutorAllowsScreenshotWhenOnlyAccessibilityIsMissing() async throws {
        let backend = PermissionRecordingComputerUseBackend(
            status: .permissionStatus(
                screenRecordingGranted: true,
                accessibilityGranted: false
            )
        )
        let executor = ComputerUseToolExecutor(
            backend: backend,
            artifactDirectory: temporaryArtifactDirectory(prefix: "QuillCodeComputerUsePreflightTests")
        )

        let result = try await assertScreenshotSucceeds(executor)
        let actions = await backend.recordedActions()

        XCTAssertEqual(actions, ["screenshot"])
        XCTAssertEqual(result.artifacts.count, 1)
    }

    func testComputerUseToolExecutorReportsUnavailableBackendBeforePermissions() async throws {
        let backend = PermissionRecordingComputerUseBackend(
            status: .unavailable("Computer Use backend is not running.")
        )
        let executor = ComputerUseToolExecutor(backend: backend)

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerClick.name,
            argumentsJSON: #"{"x":10,"y":20}"#
        ))
        let result = try XCTUnwrap(toolResult)
        let actions = await backend.recordedActions()

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Computer Use click is unavailable: Computer Use backend is not running."
        )
        XCTAssertEqual(actions, [])
    }

    func testComputerUseToolExecutorIgnoresUnknownToolsEvenWhenBackendUnavailable() async throws {
        let backend = PermissionRecordingComputerUseBackend(
            status: .unavailable("Computer Use backend is not running.")
        )
        let executor = ComputerUseToolExecutor(backend: backend)

        let toolResult = await executor.execute(ToolCall(
            name: "host.unknown.tool",
            argumentsJSON: "{}"
        ))

        XCTAssertNil(toolResult)
    }

    func testUnavailableBackendReturnsPreflightStatus() async throws {
        let backend = UnavailableComputerUseBackend(
            status: .unsupportedPlatform("Computer Use is not wired on this platform.")
        )
        let executor = ComputerUseToolExecutor(backend: backend)

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerScreenshot.name,
            argumentsJSON: "{}"
        ))
        let result = try XCTUnwrap(toolResult)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Computer Use screenshot is unavailable: Unsupported platform: Computer Use is not wired on this platform."
        )
    }
}

private extension ComputerUseToolExecutorTests {
    func assertScreenshotSucceeds(_ executor: ComputerUseToolExecutor) async throws -> ToolResult {
        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerScreenshot.name,
            argumentsJSON: "{}"
        ))
        let result = try XCTUnwrap(toolResult)
        XCTAssertTrue(result.ok)
        let artifact = try XCTUnwrap(result.artifacts.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact))
        return result
    }

    func executeStandardInputActions(with executor: ComputerUseToolExecutor) async {
        for call in standardInputActions() {
            _ = await executor.execute(call)
        }
    }

    func temporaryArtifactDirectory(prefix: String = "QuillCodeComputerUseTests") -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private func expectedRecordedActions() -> [String] {
    [
        "screenshot",
        "leftClick:10,20",
        "type:hello",
        "scroll:1,-2",
        "move:30,40",
        "key:return"
    ]
}

private func standardInputActions() -> [ToolCall] {
    [
        ToolCall(name: ToolDefinition.computerClick.name, argumentsJSON: #"{"x":10,"y":20}"#),
        ToolCall(name: ToolDefinition.computerType.name, argumentsJSON: #"{"text":"hello"}"#),
        ToolCall(name: ToolDefinition.computerScroll.name, argumentsJSON: #"{"dx":1,"dy":-2}"#),
        ToolCall(name: ToolDefinition.computerMove.name, argumentsJSON: #"{"x":30,"y":40}"#),
        ToolCall(name: ToolDefinition.computerKey.name, argumentsJSON: #"{"key":"return"}"#)
    ]
}

private func accessibilityPreflightCases() -> [(call: ToolCall, expectedError: String)] {
    [
        (
            ToolCall(name: ToolDefinition.computerClick.name, argumentsJSON: #"{"x":10,"y":20}"#),
            "Computer Use click needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
        ),
        (
            ToolCall(name: ToolDefinition.computerType.name, argumentsJSON: #"{"text":"hello"}"#),
            "Computer Use typing needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
        ),
        (
            ToolCall(name: ToolDefinition.computerScroll.name, argumentsJSON: #"{"dx":0,"dy":100}"#),
            "Computer Use scroll needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
        ),
        (
            ToolCall(name: ToolDefinition.computerMove.name, argumentsJSON: #"{"x":10,"y":20}"#),
            "Computer Use cursor movement needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
        ),
        (
            ToolCall(name: ToolDefinition.computerKey.name, argumentsJSON: #"{"key":"return"}"#),
            "Computer Use keyboard needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
        )
    ]
}

private actor PermissionRecordingComputerUseBackend: ComputerUseBackend {
    nonisolated let status: ComputerUseStatus
    private var actions: [String] = []

    init(status: ComputerUseStatus) {
        self.status = status
    }

    func recordedActions() -> [String] {
        actions
    }

    func screenshot() async throws -> ComputerScreenshot {
        actions.append("screenshot")
        return ComputerScreenshot(width: 1, height: 1, pngBase64: "iVBORw0KGgo=")
    }

    func leftClick(x: Int, y: Int) async throws {
        actions.append("leftClick:\(x),\(y)")
    }

    func type(_ text: String) async throws {
        actions.append("type:\(text)")
    }

    func scroll(dx: Int, dy: Int) async throws {
        actions.append("scroll:\(dx),\(dy)")
    }

    func moveCursor(x: Int, y: Int) async throws {
        actions.append("move:\(x),\(y)")
    }

    func pressKey(_ key: String) async throws {
        actions.append("key:\(key)")
    }
}
