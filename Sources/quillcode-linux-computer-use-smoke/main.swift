import Foundation
import QuillComputerUseKit

@main
struct LinuxComputerUseSmoke {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeLinuxComputerUseSmoke-\(UUID().uuidString)")
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
        try oneByOnePNGData().write(to: png)
        try writeExecutable(
            at: bin.appendingPathComponent("scrot"),
            content: """
            #!/bin/sh
            cp \(shellSingleQuoted(png.path)) "$1"
            """
        )
        try writeExecutable(
            at: bin.appendingPathComponent("xdotool"),
            content: """
            #!/bin/sh
            printf '%s\\n' "$*" >> \(shellSingleQuoted(xdotoolLog.path))
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
        try require(report.session == .x11, "Expected X11 session, got \(report.session).")
        try require(
            report.availableHelpers == ["scrot", "xdotool"],
            "Expected fake helpers, got \(report.availableHelpers)."
        )
        try require(report.status.available, "Expected available Computer Use status.")

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

        try require(
            screenshot.width == 1 && screenshot.height == 1,
            "Expected 1x1 screenshot, got \(screenshot.width)x\(screenshot.height)."
        )
        let xdotoolCommands = try String(contentsOf: xdotoolLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        try require(
            xdotoolCommands == [
                "mousemove 10 20",
                "click 1",
                "type --clearmodifiers --delay 0 -- hello",
                "click 5",
                "key --clearmodifiers Return"
            ],
            "Unexpected xdotool commands: \(xdotoolCommands)."
        )

        print("Linux Computer Use helper smoke passed.")
    }
}

private struct SmokeFailure: Error, CustomStringConvertible {
    var description: String
}

private func require(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw SmokeFailure(description: message)
    }
}

private func shellSingleQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func oneByOnePNGData() -> Data {
    Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!
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
