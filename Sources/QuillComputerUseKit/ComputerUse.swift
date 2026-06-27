import Foundation
import QuillCodeCore

public struct ComputerScreenshot: Codable, Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var pngBase64: String

    public init(width: Int, height: Int, pngBase64: String) {
        self.width = width
        self.height = height
        self.pngBase64 = pngBase64
    }
}

public struct ComputerScreenshotToolOutput: Codable, Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var path: String?

    public init(width: Int, height: Int, path: String?) {
        self.width = width
        self.height = height
        self.path = path
    }
}

public enum ComputerUseError: Error, CustomStringConvertible, Sendable {
    case permissionDenied(String)
    case unsupportedPlatform(String)
    case unavailable(String)

    public var description: String {
        switch self {
        case .permissionDenied(let message):
            return "Computer Use permission denied: \(message)"
        case .unsupportedPlatform(let message):
            return "Computer Use unsupported: \(message)"
        case .unavailable(let message):
            return "Computer Use unavailable: \(message)"
        }
    }
}

public protocol ComputerUseBackend: Sendable {
    var status: ComputerUseStatus { get }
    func screenshot() async throws -> ComputerScreenshot
    func leftClick(x: Int, y: Int) async throws
    func type(_ text: String) async throws
    func scroll(dx: Int, dy: Int) async throws
    func moveCursor(x: Int, y: Int) async throws
    func pressKey(_ key: String) async throws
}

public struct ComputerUseStatus: Codable, Sendable, Hashable {
    public var available: Bool
    public var screenRecordingGranted: Bool
    public var accessibilityGranted: Bool
    public var message: String
    public var unavailableReason: String?

    public init(
        available: Bool,
        screenRecordingGranted: Bool,
        accessibilityGranted: Bool,
        message: String,
        unavailableReason: String? = nil
    ) {
        self.available = available
        self.screenRecordingGranted = screenRecordingGranted
        self.accessibilityGranted = accessibilityGranted
        self.message = message
        self.unavailableReason = unavailableReason
    }

    public static func permissionStatus(
        screenRecordingGranted: Bool,
        accessibilityGranted: Bool
    ) -> ComputerUseStatus {
        let available = screenRecordingGranted && accessibilityGranted
        let message: String
        switch (screenRecordingGranted, accessibilityGranted) {
        case (true, true):
            message = "Computer Use ready"
        case (false, false):
            message = "Needs Screen Recording + Accessibility"
        case (false, true):
            message = "Needs Screen Recording"
        case (true, false):
            message = "Needs Accessibility"
        }
        return ComputerUseStatus(
            available: available,
            screenRecordingGranted: screenRecordingGranted,
            accessibilityGranted: accessibilityGranted,
            message: message
        )
    }

    public static func unavailable(_ reason: String) -> ComputerUseStatus {
        ComputerUseStatus(
            available: false,
            screenRecordingGranted: false,
            accessibilityGranted: false,
            message: reason,
            unavailableReason: reason
        )
    }

    public static func unsupportedPlatform(_ reason: String) -> ComputerUseStatus {
        unavailable("Unsupported platform: \(reason)")
    }
}

public actor StubComputerUseBackend: ComputerUseBackend {
    public private(set) var actions: [String] = []

    public nonisolated var status: ComputerUseStatus {
        .permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: true
        )
    }

    public init() {}

    public func recordedActions() -> [String] {
        actions
    }

    public func screenshot() async throws -> ComputerScreenshot {
        actions.append("screenshot")
        return ComputerScreenshot(width: 1, height: 1, pngBase64: "iVBORw0KGgo=")
    }

    public func leftClick(x: Int, y: Int) async throws {
        actions.append("leftClick:\(x),\(y)")
    }

    public func type(_ text: String) async throws {
        actions.append("type:\(text)")
    }

    public func scroll(dx: Int, dy: Int) async throws {
        actions.append("scroll:\(dx),\(dy)")
    }

    public func moveCursor(x: Int, y: Int) async throws {
        actions.append("move:\(x),\(y)")
    }

    public func pressKey(_ key: String) async throws {
        actions.append("key:\(key)")
    }
}

public struct ComputerUseToolExecutor: Sendable {
    private let backend: any ComputerUseBackend
    private let artifactDirectory: URL

    public init(
        backend: any ComputerUseBackend,
        artifactDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCode", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)
    ) {
        self.backend = backend
        self.artifactDirectory = artifactDirectory
    }

    public func execute(_ call: ToolCall) async -> ToolResult? {
        if let failure = preflightFailure(for: call.name) {
            return failure
        }

        do {
            let args = try ToolArguments(call.argumentsJSON)
            switch call.name {
            case ToolDefinition.computerScreenshot.name:
                let screenshot = try await backend.screenshot()
                let path = try writeScreenshotArtifact(screenshot)
                let output = ComputerScreenshotToolOutput(
                    width: screenshot.width,
                    height: screenshot.height,
                    path: path
                )
                return ToolResult(
                    ok: true,
                    stdout: (try? JSONHelpers.encodePretty(output)) ?? """
                    {"width":\(screenshot.width),"height":\(screenshot.height)}
                    """,
                    artifacts: path.map { [$0] } ?? []
                )
            case ToolDefinition.computerClick.name:
                let x = try args.requiredInt("x")
                let y = try args.requiredInt("y")
                try await backend.leftClick(x: x, y: y)
                return ToolResult(ok: true, stdout: "Clicked \(x) \(y).")
            case ToolDefinition.computerType.name:
                let text = try args.requiredString("text")
                try await backend.type(text)
                return ToolResult(ok: true, stdout: "Typed \(text.count) characters.")
            case ToolDefinition.computerScroll.name:
                let dx = args.int("dx") ?? 0
                let dy = args.int("dy") ?? 0
                try await backend.scroll(dx: dx, dy: dy)
                return ToolResult(ok: true, stdout: "Scrolled dx \(dx), dy \(dy).")
            case ToolDefinition.computerMove.name:
                let x = try args.requiredInt("x")
                let y = try args.requiredInt("y")
                try await backend.moveCursor(x: x, y: y)
                return ToolResult(ok: true, stdout: "Moved cursor to \(x) \(y).")
            case ToolDefinition.computerKey.name:
                let key = try args.requiredString("key")
                try await backend.pressKey(key)
                return ToolResult(ok: true, stdout: "Pressed \(key).")
            default:
                return nil
            }
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func preflightFailure(for toolName: String) -> ToolResult? {
        guard Self.isComputerUseTool(toolName) else {
            return nil
        }

        let status = backend.status
        if let unavailableReason = status.unavailableReason {
            return ToolResult(
                ok: false,
                error: Self.unavailablePreflightMessage(
                    reason: unavailableReason,
                    toolName: toolName
                )
            )
        }

        let missingPermissions = Self.missingPermissions(for: toolName, status: status)
        guard !missingPermissions.isEmpty else {
            return nil
        }

        return ToolResult(
            ok: false,
            error: Self.permissionPreflightMessage(
                missingPermissions: missingPermissions,
                toolName: toolName
            )
        )
    }

    private static func isComputerUseTool(_ toolName: String) -> Bool {
        ToolDefinition.computerUseDefinitions.contains { $0.name == toolName }
    }

    private static func missingPermissions(
        for toolName: String,
        status: ComputerUseStatus
    ) -> [ComputerUsePermissionRequirement] {
        switch toolName {
        case ToolDefinition.computerScreenshot.name:
            return status.screenRecordingGranted ? [] : [.screenRecording]
        case ToolDefinition.computerClick.name,
             ToolDefinition.computerType.name,
             ToolDefinition.computerScroll.name,
             ToolDefinition.computerMove.name,
             ToolDefinition.computerKey.name:
            return status.accessibilityGranted ? [] : [.accessibility]
        default:
            return []
        }
    }

    private static func permissionPreflightMessage(
        missingPermissions: [ComputerUsePermissionRequirement],
        toolName: String
    ) -> String {
        let permissionList = missingPermissions
            .map(\.displayName)
            .joined(separator: " + ")
        return "Computer Use \(toolDisplayName(for: toolName)) needs \(permissionList). "
            + "Open Computer Use setup from Settings, grant \(permissionList), then refresh status."
    }

    private static func unavailablePreflightMessage(
        reason: String,
        toolName: String
    ) -> String {
        "Computer Use \(toolDisplayName(for: toolName)) is unavailable: \(reason)"
    }

    private static func toolDisplayName(for toolName: String) -> String {
        switch toolName {
        case ToolDefinition.computerScreenshot.name:
            return "screenshot"
        case ToolDefinition.computerClick.name:
            return "click"
        case ToolDefinition.computerType.name:
            return "typing"
        case ToolDefinition.computerScroll.name:
            return "scroll"
        case ToolDefinition.computerMove.name:
            return "cursor movement"
        case ToolDefinition.computerKey.name:
            return "keyboard"
        default:
            return "action"
        }
    }

    private func writeScreenshotArtifact(_ screenshot: ComputerScreenshot) throws -> String? {
        guard let data = Data(base64Encoded: screenshot.pngBase64) else {
            return nil
        }
        try FileManager.default.createDirectory(
            at: artifactDirectory,
            withIntermediateDirectories: true
        )
        let url = artifactDirectory
            .appendingPathComponent("screenshot-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("png")
        try data.write(to: url, options: .atomic)
        return url.path
    }
}

private enum ComputerUsePermissionRequirement {
    case screenRecording
    case accessibility

    var displayName: String {
        switch self {
        case .screenRecording:
            return "Screen Recording"
        case .accessibility:
            return "Accessibility"
        }
    }
}

public extension ToolDefinition {
    static let computerUseDefinitions: [ToolDefinition] = [
        .computerScreenshot,
        .computerClick,
        .computerType,
        .computerScroll,
        .computerMove,
        .computerKey
    ]

    static let computerScreenshot = ToolDefinition(
        name: "host.computer.screenshot",
        description: "Capture a screenshot of the active desktop.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .computer,
        risk: .read
    )

    static let computerClick = ToolDefinition(
        name: "host.computer.click",
        description: "Click a point on the active desktop.",
        parametersJSON: #"{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"}},"required":["x","y"]}"#,
        host: .computer,
        risk: .destructive
    )

    static let computerType = ToolDefinition(
        name: "host.computer.type",
        description: "Type text into the focused application.",
        parametersJSON: #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#,
        host: .computer,
        risk: .destructive
    )

    static let computerScroll = ToolDefinition(
        name: "host.computer.scroll",
        description: "Scroll the active desktop view by a delta.",
        parametersJSON: #"{"type":"object","properties":{"dx":{"type":"integer"},"dy":{"type":"integer"}}}"#,
        host: .computer,
        risk: .destructive
    )

    static let computerMove = ToolDefinition(
        name: "host.computer.move",
        description: "Move the cursor to a point on the active desktop.",
        parametersJSON: #"{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"}},"required":["x","y"]}"#,
        host: .computer,
        risk: .destructive
    )

    static let computerKey = ToolDefinition(
        name: "host.computer.key",
        description: "Press a keyboard key or shortcut in the focused application.",
        parametersJSON: #"{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}"#,
        host: .computer,
        risk: .destructive
    )
}
