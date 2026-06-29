import Foundation

public struct LinuxComputerUseCommandResult: Sendable, Hashable {
    public var stdout: Data
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: Data = Data(), stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public actor LinuxComputerUseBackend: ComputerUseBackend {
    public typealias CommandRunner = @Sendable (_ arguments: [String]) async throws -> LinuxComputerUseCommandResult

    public nonisolated let status: ComputerUseStatus

    private let session: LinuxComputerUseSession
    private let availableHelpers: Set<String>
    private let runCommand: CommandRunner
    private let temporaryDirectory: URL

    public init(
        report: LinuxComputerUseCapabilityReport,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        commandRunner: @escaping CommandRunner = LinuxComputerUseProcessRunner.run
    ) {
        self.status = report.status
        self.session = report.session
        self.availableHelpers = Set(report.availableHelpers)
        self.runCommand = commandRunner
        self.temporaryDirectory = temporaryDirectory
    }

    public func screenshot() async throws -> ComputerScreenshot {
        let url = temporaryDirectory
            .appendingPathComponent("quillcode-linux-screenshot-\(UUID().uuidString)")
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        switch session {
        case .wayland:
            try await runChecked(["grim", url.path])
        case .x11:
            if availableHelpers.contains("import") {
                try await runChecked(["import", "-window", "root", url.path])
            } else if availableHelpers.contains("scrot") {
                try await runChecked(["scrot", url.path])
            } else {
                throw ComputerUseError.unavailable("Linux X11 screenshot helper is unavailable.")
            }
        case .none:
            throw ComputerUseError.unavailable("Linux Computer Use needs a graphical session.")
        }

        let data = try Data(contentsOf: url)
        let dimensions = try Self.pngDimensions(data)
        return ComputerScreenshot(
            width: dimensions.width,
            height: dimensions.height,
            pngBase64: data.base64EncodedString()
        )
    }

    public func leftClick(x: Int, y: Int) async throws {
        try await moveCursor(x: x, y: y)
        switch session {
        case .wayland:
            try await runChecked(["ydotool", "click", "0xC0"])
        case .x11:
            try await runChecked(["xdotool", "click", "1"])
        case .none:
            throw ComputerUseError.unavailable("Linux Computer Use needs a graphical session.")
        }
    }

    public func type(_ text: String) async throws {
        switch session {
        case .wayland:
            if availableHelpers.contains("ydotool") {
                try await runChecked(["ydotool", "type", text])
            } else if availableHelpers.contains("wtype") {
                try await runChecked(["wtype", text])
            } else {
                throw ComputerUseError.unavailable("Linux Wayland typing helper is unavailable.")
            }
        case .x11:
            try await runChecked(["xdotool", "type", "--clearmodifiers", "--delay", "0", "--", text])
        case .none:
            throw ComputerUseError.unavailable("Linux Computer Use needs a graphical session.")
        }
    }

    public func scroll(dx: Int, dy: Int) async throws {
        let steps = scrollButtonPresses(dx: dx, dy: dy)
        for button in steps {
            switch session {
            case .wayland:
                try await runChecked(["ydotool", "click", button.waylandCode])
            case .x11:
                try await runChecked(["xdotool", "click", button.x11Code])
            case .none:
                throw ComputerUseError.unavailable("Linux Computer Use needs a graphical session.")
            }
        }
    }

    public func moveCursor(x: Int, y: Int) async throws {
        switch session {
        case .wayland:
            try await runChecked(["ydotool", "mousemove", "--absolute", String(x), String(y)])
        case .x11:
            try await runChecked(["xdotool", "mousemove", String(x), String(y)])
        case .none:
            throw ComputerUseError.unavailable("Linux Computer Use needs a graphical session.")
        }
    }

    public func pressKey(_ key: String) async throws {
        switch session {
        case .wayland:
            try await runChecked(["ydotool", "key", key])
        case .x11:
            try await runChecked(["xdotool", "key", "--clearmodifiers", key])
        case .none:
            throw ComputerUseError.unavailable("Linux Computer Use needs a graphical session.")
        }
    }

    private func runChecked(_ arguments: [String]) async throws {
        let result = try await runCommand(arguments)
        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ComputerUseError.unavailable(
                detail.isEmpty
                    ? "Linux helper failed: \(arguments.joined(separator: " "))"
                    : "Linux helper failed: \(detail)"
            )
        }
    }

    private func scrollButtonPresses(dx: Int, dy: Int) -> [LinuxScrollButton] {
        var buttons: [LinuxScrollButton] = []
        buttons.append(contentsOf: repeatedScrollButtons(
            positive: dx,
            positiveButton: .right,
            negativeButton: .left
        ))
        buttons.append(contentsOf: repeatedScrollButtons(
            positive: dy,
            positiveButton: .down,
            negativeButton: .up
        ))
        return buttons
    }

    private func repeatedScrollButtons(
        positive value: Int,
        positiveButton: LinuxScrollButton,
        negativeButton: LinuxScrollButton
    ) -> [LinuxScrollButton] {
        guard value != 0 else { return [] }
        let count = min(20, max(1, abs(value) / 120))
        return Array(repeating: value > 0 ? positiveButton : negativeButton, count: count)
    }

    private static func pngDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        guard data.count >= 24,
              data[0] == 0x89,
              data[1] == 0x50,
              data[2] == 0x4E,
              data[3] == 0x47 else {
            throw ComputerUseError.unavailable("Linux screenshot helper did not produce PNG data.")
        }
        let width = Int(data[16]) << 24
            | Int(data[17]) << 16
            | Int(data[18]) << 8
            | Int(data[19])
        let height = Int(data[20]) << 24
            | Int(data[21]) << 16
            | Int(data[22]) << 8
            | Int(data[23])
        return (width, height)
    }
}

private enum LinuxScrollButton {
    case up
    case down
    case left
    case right

    var x11Code: String {
        switch self {
        case .up:
            return "4"
        case .down:
            return "5"
        case .left:
            return "6"
        case .right:
            return "7"
        }
    }

    var waylandCode: String {
        switch self {
        case .up:
            return "0xC4"
        case .down:
            return "0xC5"
        case .left:
            return "0xC6"
        case .right:
            return "0xC7"
        }
    }
}

public struct LinuxComputerUseProcessRunner: Sendable {
    private let environment: [String: String]?

    public init(environment: [String: String]? = nil) {
        self.environment = environment
    }

    public func run(_ arguments: [String]) async throws -> LinuxComputerUseCommandResult {
        guard let executable = arguments.first else {
            throw ComputerUseError.unavailable("Linux helper command is empty.")
        }
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + Array(arguments.dropFirst())
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return LinuxComputerUseCommandResult(
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            exitCode: process.terminationStatus
        )
    }

    public static func run(_ arguments: [String]) async throws -> LinuxComputerUseCommandResult {
        try await LinuxComputerUseProcessRunner().run(arguments)
    }
}
