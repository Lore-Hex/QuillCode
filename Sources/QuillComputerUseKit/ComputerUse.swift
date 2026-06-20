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

    public init(
        available: Bool,
        screenRecordingGranted: Bool,
        accessibilityGranted: Bool,
        message: String
    ) {
        self.available = available
        self.screenRecordingGranted = screenRecordingGranted
        self.accessibilityGranted = accessibilityGranted
        self.message = message
    }
}

public actor StubComputerUseBackend: ComputerUseBackend {
    public private(set) var actions: [String] = []

    public nonisolated var status: ComputerUseStatus {
        ComputerUseStatus(
            available: true,
            screenRecordingGranted: true,
            accessibilityGranted: true,
            message: "Stub Computer Use backend ready."
        )
    }

    public init() {}

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

public extension ToolDefinition {
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
}
