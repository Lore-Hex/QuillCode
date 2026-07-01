import Foundation

public enum ProjectExtensionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case plugin
    case skill
    case mcpServer = "mcp_server"

    public var title: String {
        switch self {
        case .plugin:
            return "Plugin"
        case .skill:
            return "Skill"
        case .mcpServer:
            return "MCP"
        }
    }
}

public enum ProjectExtensionTransport: String, Codable, Sendable, Hashable {
    case stdio
    case http
    case sse
}

public struct ProjectExtensionManifest: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ProjectExtensionKind
    public var name: String
    public var summary: String
    public var version: String?
    public var sourceURL: String?
    public var relativePath: String
    public var isEnabled: Bool
    public var transport: ProjectExtensionTransport?
    public var launchExecutable: String?
    public var launchCommand: String?
    public var launchArguments: [String]?
    public var installCommand: String?
    public var installTimeoutSeconds: Int?
    public var updateCommand: String?
    public var updateTimeoutSeconds: Int?

    public init(
        id: String,
        kind: ProjectExtensionKind,
        name: String,
        summary: String = "",
        version: String? = nil,
        sourceURL: String? = nil,
        relativePath: String,
        isEnabled: Bool = true,
        transport: ProjectExtensionTransport? = nil,
        launchExecutable: String? = nil,
        launchCommand: String? = nil,
        launchArguments: [String]? = nil,
        installCommand: String? = nil,
        installTimeoutSeconds: Int? = nil,
        updateCommand: String? = nil,
        updateTimeoutSeconds: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
        self.version = version
        self.sourceURL = sourceURL
        self.relativePath = relativePath
        self.isEnabled = isEnabled
        self.transport = transport
        self.launchExecutable = launchExecutable
        self.launchCommand = launchCommand
        self.launchArguments = launchArguments
        self.installCommand = installCommand
        self.installTimeoutSeconds = installTimeoutSeconds
        self.updateCommand = updateCommand
        self.updateTimeoutSeconds = updateTimeoutSeconds
    }
}
