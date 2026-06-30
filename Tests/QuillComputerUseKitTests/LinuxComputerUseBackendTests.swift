import XCTest
import QuillComputerUseKit

final class LinuxComputerUseBackendTests: XCTestCase {
    func testLinuxWaylandBackendRoutesHelperCommands() async throws {
        let runner = RecordingLinuxCommandRunner()
        let backend = LinuxComputerUseBackend(
            report: readyWaylandReport(),
            commandRunner: runner.run
        )

        let screenshot = try await runStandardLinuxActions(on: backend, scrollDX: 120, scrollDY: -240)

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
        let runner = RecordingLinuxCommandRunner()
        let backend = LinuxComputerUseBackend(
            report: readyX11Report(),
            commandRunner: runner.run
        )

        let screenshot = try await runStandardLinuxActions(on: backend, scrollDX: -120, scrollDY: 240)

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
        let runner = RecordingLinuxCommandRunner(
            failureExecutable: "xdotool",
            failureResult: LinuxComputerUseCommandResult(
                stderr: "no display\n",
                exitCode: 2
            )
        )
        let backend = LinuxComputerUseBackend(
            report: readyX11Report(),
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
        let helperEnvironment = try installFakeX11Helpers(in: root)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let report = LinuxComputerUseCapabilityDetector(environment: helperEnvironment.environment).report()
        XCTAssertEqual(report.session, .x11)
        XCTAssertEqual(report.availableHelpers, ["scrot", "xdotool"])
        XCTAssertTrue(report.status.available)

        let processRunner = LinuxComputerUseProcessRunner(
            environment: ["PATH": helperEnvironment.environment["PATH"] ?? ""]
        )
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
        XCTAssertEqual(try helperEnvironment.loggedCommands(), [
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

private func readyWaylandReport() -> LinuxComputerUseCapabilityReport {
    LinuxComputerUseCapabilityDetector(
        environment: [
            "XDG_SESSION_TYPE": "wayland",
            "WAYLAND_DISPLAY": "wayland-0"
        ],
        executableLookup: { ["grim", "ydotool"].contains($0) }
    ).report()
}

private func readyX11Report() -> LinuxComputerUseCapabilityReport {
    LinuxComputerUseCapabilityDetector(
        environment: [
            "XDG_SESSION_TYPE": "x11",
            "DISPLAY": ":0"
        ],
        executableLookup: { ["scrot", "xdotool"].contains($0) }
    ).report()
}

private func runStandardLinuxActions(
    on backend: LinuxComputerUseBackend,
    scrollDX: Int,
    scrollDY: Int
) async throws -> ComputerScreenshot {
    let screenshot = try await backend.screenshot()
    try await backend.leftClick(x: 10, y: 20)
    try await backend.type("hello")
    try await backend.scroll(dx: scrollDX, dy: scrollDY)
    try await backend.moveCursor(x: 30, y: 40)
    try await backend.pressKey("Return")
    return screenshot
}

private struct FakeX11HelperEnvironment {
    let environment: [String: String]
    let xdotoolLog: URL

    func loggedCommands() throws -> [String] {
        try String(contentsOf: xdotoolLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }
}

private func installFakeX11Helpers(in root: URL) throws -> FakeX11HelperEnvironment {
    let bin = root.appendingPathComponent("bin")
    let png = root.appendingPathComponent("one-by-one.png")
    let xdotoolLog = root.appendingPathComponent("xdotool.log")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
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
    return FakeX11HelperEnvironment(
        environment: [
            "XDG_SESSION_TYPE": "x11",
            "DISPLAY": ":99",
            "PATH": path
        ],
        xdotoolLog: xdotoolLog
    )
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
