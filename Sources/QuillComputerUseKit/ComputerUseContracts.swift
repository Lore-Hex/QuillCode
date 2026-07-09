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
    public var foregroundApplication: ComputerUseApplication?
    public var accessibilitySnapshot: ComputerUseAccessibilitySnapshot?
    public var visualSummary: String?

    public init(
        width: Int,
        height: Int,
        path: String?,
        foregroundApplication: ComputerUseApplication? = nil,
        accessibilitySnapshot: ComputerUseAccessibilitySnapshot? = nil,
        visualSummary: String? = nil
    ) {
        self.width = width
        self.height = height
        self.path = path
        self.foregroundApplication = foregroundApplication
        self.accessibilitySnapshot = accessibilitySnapshot?.isEmpty == true ? nil : accessibilitySnapshot
        self.visualSummary = Self.trimmed(visualSummary)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ComputerUseAccessibilitySnapshot: Codable, Sendable, Hashable {
    public var elements: [ComputerUseAccessibilityElement]

    public init(elements: [ComputerUseAccessibilityElement]) {
        self.elements = elements.filter { !$0.isEmpty }
    }

    public var isEmpty: Bool {
        elements.isEmpty
    }

    public var summary: String? {
        let labels = elements.prefix(8).compactMap(\.summary)
        guard !labels.isEmpty else { return nil }
        return labels.joined(separator: "; ")
    }
}

public struct ComputerUseAccessibilityElement: Codable, Sendable, Hashable {
    public var role: String?
    public var label: String?
    public var value: String?

    public init(role: String? = nil, label: String? = nil, value: String? = nil) {
        self.role = Self.trimmed(role)
        self.label = Self.trimmed(label)
        self.value = Self.trimmed(value)
    }

    public var isEmpty: Bool {
        role == nil && label == nil && value == nil
    }

    public var summary: String? {
        let title: String?
        if let label, let value, label != value {
            title = "\(label) (\(value))"
        } else {
            title = label ?? value
        }
        guard let title, !title.isEmpty else { return role }
        guard let role, !role.isEmpty else { return title }
        return "\(role): \(title)"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }
}

public struct ComputerUseApplication: Codable, Sendable, Hashable {
    public var name: String?
    public var bundleIdentifier: String?

    public init(name: String? = nil, bundleIdentifier: String? = nil) {
        self.name = Self.trimmed(name)
        self.bundleIdentifier = Self.trimmed(bundleIdentifier)
    }

    public var displayLabel: String {
        if let name, !name.isEmpty { return name }
        if let bundleIdentifier, !bundleIdentifier.isEmpty { return bundleIdentifier }
        return "Unknown application"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

public protocol ComputerUseForegroundApplicationProviding: Sendable {
    func foregroundApplication() async -> ComputerUseApplication?
}

public protocol ComputerUseAccessibilitySnapshotProviding: Sendable {
    func accessibilitySnapshot(limit: Int) async -> ComputerUseAccessibilitySnapshot?
}
