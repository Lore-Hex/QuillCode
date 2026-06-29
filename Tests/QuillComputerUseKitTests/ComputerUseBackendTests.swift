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

    func testUnavailableStatusCarriesBackendReasonSeparatelyFromPermissions() {
        let status = ComputerUseStatus.unavailable("Computer Use backend is not running.")

        XCTAssertFalse(status.available)
        XCTAssertFalse(status.screenRecordingGranted)
        XCTAssertFalse(status.accessibilityGranted)
        XCTAssertEqual(status.message, "Computer Use backend is not running.")
        XCTAssertEqual(status.unavailableReason, "Computer Use backend is not running.")
    }

    func testUnsupportedPlatformStatusIsUnavailableWithPlatformReason() {
        let status = ComputerUseStatus.unsupportedPlatform("Linux backend not configured.")

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.message, "Unsupported platform: Linux backend not configured.")
        XCTAssertEqual(status.unavailableReason, "Unsupported platform: Linux backend not configured.")
    }

    func testComputerUseStatusDecodesOlderPayloadWithoutUnavailableReason() throws {
        let status = try JSONDecoder().decode(
            ComputerUseStatus.self,
            from: Data("""
            {
              "available": false,
              "screenRecordingGranted": true,
              "accessibilityGranted": false,
              "message": "Needs Accessibility"
            }
            """.utf8)
        )

        XCTAssertFalse(status.available)
        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertFalse(status.accessibilityGranted)
        XCTAssertEqual(status.message, "Needs Accessibility")
        XCTAssertNil(status.unavailableReason)
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
        let calls: [(ToolCall, String)] = [
            (
                ToolCall(
                    name: ToolDefinition.computerClick.name,
                    argumentsJSON: #"{"x":10,"y":20}"#
                ),
                "Computer Use click needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
            ),
            (
                ToolCall(
                    name: ToolDefinition.computerType.name,
                    argumentsJSON: #"{"text":"hello"}"#
                ),
                "Computer Use typing needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
            ),
            (
                ToolCall(
                    name: ToolDefinition.computerScroll.name,
                    argumentsJSON: #"{"dx":0,"dy":100}"#
                ),
                "Computer Use scroll needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
            ),
            (
                ToolCall(
                    name: ToolDefinition.computerMove.name,
                    argumentsJSON: #"{"x":10,"y":20}"#
                ),
                "Computer Use cursor movement needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
            ),
            (
                ToolCall(
                    name: ToolDefinition.computerKey.name,
                    argumentsJSON: #"{"key":"return"}"#
                ),
                "Computer Use keyboard needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
            )
        ]

        for (call, expectedError) in calls {
            let toolResult = await executor.execute(call)
            let result = try XCTUnwrap(toolResult)
            XCTAssertFalse(result.ok)
            XCTAssertEqual(result.error, expectedError)
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
        let artifactDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeComputerUsePreflightTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: artifactDirectory)
        }
        let executor = ComputerUseToolExecutor(
            backend: backend,
            artifactDirectory: artifactDirectory
        )

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.computerScreenshot.name,
            argumentsJSON: "{}"
        ))
        let result = try XCTUnwrap(toolResult)
        let actions = await backend.recordedActions()

        XCTAssertTrue(result.ok)
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

    func testDefaultBackendFactoryReportsCurrentPlatformState() {
        let status = ComputerUseBackendFactory.platformDefault().backend().status

        XCTAssertEqual(status.available, status.screenRecordingGranted && status.accessibilityGranted)
        XCTAssertFalse(status.message.isEmpty)
    }

    func testLinuxComputerUseSessionDetectionPrefersWayland() {
        let session = LinuxComputerUseSession.detect(from: [
            "XDG_SESSION_TYPE": "wayland",
            "WAYLAND_DISPLAY": "wayland-0",
            "DISPLAY": ":0"
        ])

        XCTAssertEqual(session, .wayland)
    }

    func testLinuxComputerUseDetectorReportsMissingGraphicalSession() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [:],
            executableLookup: { _ in false }
        ).report()

        XCTAssertEqual(report.session, .none)
        XCTAssertEqual(report.availableHelpers, [])
        XCTAssertEqual(report.missingHelpers, [])
        XCTAssertFalse(report.status.available)
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use needs a graphical Wayland or X11 session."
        )
    }

    func testLinuxComputerUseDetectorReportsMissingWaylandHelpers() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [
                "XDG_SESSION_TYPE": "wayland",
                "WAYLAND_DISPLAY": "wayland-0"
            ],
            executableLookup: { $0 == "grim" }
        ).report()

        XCTAssertEqual(report.session, .wayland)
        XCTAssertEqual(report.availableHelpers, ["grim"])
        XCTAssertEqual(report.missingHelpers, ["ydotool", "wtype"])
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use detected Wayland but needs helper tools: ydotool, wtype."
        )
    }

    func testLinuxComputerUseDetectorReportsCompleteWaylandHelpersAsReady() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [
                "XDG_SESSION_TYPE": "wayland",
                "WAYLAND_DISPLAY": "wayland-0"
            ],
            executableLookup: { ["grim", "ydotool"].contains($0) }
        ).report()

        XCTAssertEqual(report.session, .wayland)
        XCTAssertEqual(report.availableHelpers, ["grim", "ydotool"])
        XCTAssertEqual(report.missingHelpers, [])
        XCTAssertTrue(report.status.available)
        XCTAssertTrue(report.status.screenRecordingGranted)
        XCTAssertTrue(report.status.accessibilityGranted)
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use ready (Wayland helpers detected)."
        )
    }

    func testLinuxComputerUseDetectorReportsX11Helpers() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [
                "XDG_SESSION_TYPE": "x11",
                "DISPLAY": ":0"
            ],
            executableLookup: { $0 == "xdotool" }
        ).report()

        XCTAssertEqual(report.session, .x11)
        XCTAssertEqual(report.availableHelpers, ["xdotool"])
        XCTAssertEqual(report.missingHelpers, ["import or scrot"])
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use detected X11 but needs helper tools: import or scrot."
        )
    }

    func testLinuxComputerUseDetectorReportsCompleteX11HelpersAsReady() {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [
                "XDG_SESSION_TYPE": "x11",
                "DISPLAY": ":0"
            ],
            executableLookup: { ["scrot", "xdotool"].contains($0) }
        ).report()

        XCTAssertEqual(report.session, .x11)
        XCTAssertEqual(report.availableHelpers, ["scrot", "xdotool"])
        XCTAssertEqual(report.missingHelpers, [])
        XCTAssertTrue(report.status.available)
        XCTAssertTrue(report.status.screenRecordingGranted)
        XCTAssertTrue(report.status.accessibilityGranted)
        XCTAssertEqual(
            report.status.message,
            "Linux Computer Use ready (X11 helpers detected)."
        )
    }

    func testLinuxWaylandBackendRoutesHelperCommands() async throws {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [
                "XDG_SESSION_TYPE": "wayland",
                "WAYLAND_DISPLAY": "wayland-0"
            ],
            executableLookup: { ["grim", "ydotool"].contains($0) }
        ).report()
        let runner = RecordingLinuxCommandRunner()
        let backend = LinuxComputerUseBackend(
            report: report,
            commandRunner: runner.run
        )

        let screenshot = try await backend.screenshot()
        try await backend.leftClick(x: 10, y: 20)
        try await backend.type("hello")
        try await backend.scroll(dx: 120, dy: -240)
        try await backend.moveCursor(x: 30, y: 40)
        try await backend.pressKey("Return")

        XCTAssertEqual(screenshot.width, 1)
        XCTAssertEqual(screenshot.height, 1)
        let commands = await runner.recordedCommands()
        XCTAssertEqual(commands.count, 9)
        XCTAssertEqual(commands[0].first, "grim")
        XCTAssertTrue(commands[0].last?.hasSuffix(".png") == true)
        XCTAssertEqual(commands[1], ["ydotool", "mousemove", "--absolute", "10", "20"])
        XCTAssertEqual(commands[2], ["ydotool", "click", "0xC0"])
        XCTAssertEqual(commands[3], ["ydotool", "type", "hello"])
        XCTAssertEqual(commands[4], ["ydotool", "click", "0xC7"])
        XCTAssertEqual(commands[5], ["ydotool", "click", "0xC4"])
        XCTAssertEqual(commands[6], ["ydotool", "click", "0xC4"])
        XCTAssertEqual(commands[7], ["ydotool", "mousemove", "--absolute", "30", "40"])
        XCTAssertEqual(commands[8], ["ydotool", "key", "Return"])
    }

    func testLinuxX11BackendRoutesHelperCommands() async throws {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [
                "XDG_SESSION_TYPE": "x11",
                "DISPLAY": ":0"
            ],
            executableLookup: { ["scrot", "xdotool"].contains($0) }
        ).report()
        let runner = RecordingLinuxCommandRunner()
        let backend = LinuxComputerUseBackend(
            report: report,
            commandRunner: runner.run
        )

        let screenshot = try await backend.screenshot()
        try await backend.leftClick(x: 10, y: 20)
        try await backend.type("hello")
        try await backend.scroll(dx: -120, dy: 240)
        try await backend.moveCursor(x: 30, y: 40)
        try await backend.pressKey("Return")

        XCTAssertEqual(screenshot.width, 1)
        XCTAssertEqual(screenshot.height, 1)
        let commands = await runner.recordedCommands()
        XCTAssertEqual(commands.count, 9)
        XCTAssertEqual(commands[0].first, "scrot")
        XCTAssertTrue(commands[0].last?.hasSuffix(".png") == true)
        XCTAssertEqual(commands[1], ["xdotool", "mousemove", "10", "20"])
        XCTAssertEqual(commands[2], ["xdotool", "click", "1"])
        XCTAssertEqual(commands[3], ["xdotool", "type", "--clearmodifiers", "--delay", "0", "--", "hello"])
        XCTAssertEqual(commands[4], ["xdotool", "click", "6"])
        XCTAssertEqual(commands[5], ["xdotool", "click", "5"])
        XCTAssertEqual(commands[6], ["xdotool", "click", "5"])
        XCTAssertEqual(commands[7], ["xdotool", "mousemove", "30", "40"])
        XCTAssertEqual(commands[8], ["xdotool", "key", "--clearmodifiers", "Return"])
    }

    func testLinuxBackendReportsHelperFailure() async throws {
        let report = LinuxComputerUseCapabilityDetector(
            environment: [
                "XDG_SESSION_TYPE": "x11",
                "DISPLAY": ":0"
            ],
            executableLookup: { ["scrot", "xdotool"].contains($0) }
        ).report()
        let runner = RecordingLinuxCommandRunner(
            failureExecutable: "xdotool",
            failureResult: LinuxComputerUseCommandResult(
                stderr: "no display\n",
                exitCode: 2
            )
        )
        let backend = LinuxComputerUseBackend(
            report: report,
            commandRunner: runner.run
        )

        do {
            try await backend.moveCursor(x: 10, y: 20)
            XCTFail("Expected helper failure")
        } catch {
            XCTAssertTrue(
                String(describing: error).contains("Linux helper failed: no display"),
                "Unexpected error: \(error)"
            )
        }
    }

    func testLinuxBackendRunsFakeHelpersThroughProcessRunner() async throws {
        #if os(Linux)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeLinuxComputerUseProcessSmoke-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        let png = root.appendingPathComponent("one-by-one.png")
        let xdotoolLog = root.appendingPathComponent("xdotool.log")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(
            at: bin,
            withIntermediateDirectories: true
        )
        try RecordingLinuxCommandRunner.oneByOnePNGData().write(to: png)
        try writeExecutable(
            at: bin.appendingPathComponent("scrot"),
            content: """
            #!/bin/sh
            cp '\(png.path)' "$1"
            """
        )
        try writeExecutable(
            at: bin.appendingPathComponent("xdotool"),
            content: """
            #!/bin/sh
            printf '%s\\n' "$*" >> '\(xdotoolLog.path)'
            """
        )

        let path = "\(bin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")"
        let report = LinuxComputerUseCapabilityDetector(
            environment: [
                "XDG_SESSION_TYPE": "x11",
                "DISPLAY": ":99",
                "PATH": path
            ]
        ).report()
        XCTAssertEqual(report.session, .x11)
        XCTAssertEqual(report.availableHelpers, ["scrot", "xdotool"])
        XCTAssertTrue(report.status.available)

        let processRunner = LinuxComputerUseProcessRunner(environment: ["PATH": path])
        let backend = LinuxComputerUseBackend(
            report: report,
            commandRunner: processRunner.run
        )

        let screenshot = try await backend.screenshot()
        try await backend.leftClick(x: 10, y: 20)
        try await backend.type("hello")
        try await backend.scroll(dx: 0, dy: 120)
        try await backend.pressKey("Return")

        XCTAssertEqual(screenshot.width, 1)
        XCTAssertEqual(screenshot.height, 1)
        let xdotoolCommands = try String(contentsOf: xdotoolLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(xdotoolCommands, [
            "mousemove 10 20",
            "click 1",
            "type --clearmodifiers --delay 0 -- hello",
            "click 5",
            "key --clearmodifiers Return"
        ])
        #else
        throw XCTSkip("Linux process-runner smoke only runs on Linux.")
        #endif
    }
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

private actor RecordingLinuxCommandRunner {
    private var commands: [[String]] = []
    private let pngData: Data
    private let failureExecutable: String?
    private let failureResult: LinuxComputerUseCommandResult

    init(
        pngData: Data? = nil,
        failureExecutable: String? = nil,
        failureResult: LinuxComputerUseCommandResult = LinuxComputerUseCommandResult()
    ) {
        self.pngData = pngData ?? Self.oneByOnePNGData()
        self.failureExecutable = failureExecutable
        self.failureResult = failureResult
    }

    func run(_ arguments: [String]) async throws -> LinuxComputerUseCommandResult {
        commands.append(arguments)
        if arguments.first == failureExecutable {
            return failureResult
        }
        if shouldWriteScreenshot(for: arguments),
           let outputPath = arguments.last {
            try pngData.write(to: URL(fileURLWithPath: outputPath))
        }
        return LinuxComputerUseCommandResult()
    }

    func recordedCommands() -> [[String]] {
        commands
    }

    private nonisolated func shouldWriteScreenshot(for arguments: [String]) -> Bool {
        guard let executable = arguments.first else { return false }
        return ["grim", "scrot", "import"].contains(executable)
    }

    nonisolated static func oneByOnePNGData() -> Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        )!
    }
}

private func writeExecutable(
    at url: URL,
    content: String
) throws {
    try content.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
}
