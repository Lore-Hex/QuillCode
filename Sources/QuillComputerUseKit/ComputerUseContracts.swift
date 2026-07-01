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
