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
    /// The remote endpoint URL for `http`/`sse` transports (nil for stdio servers).
    public var serverURL: String?
    /// Extra HTTP headers to send on every request to a remote server (e.g. a static API key).
    public var headers: [String: String]?
    /// A static OAuth client ID to use instead of dynamic registration, when the server requires one.
    public var oauthClientID: String?
    public var launchExecutable: String?
    public var launchCommand: String?
    public var launchArguments: [String]?
    /// Workspace-relative root of the package that contributed this extension.
    /// Resolved and boundary-checked again immediately before use.
    public var packageRootRelativePath: String?
    /// Workspace-relative skill roots bundled by a plugin package.
    public var skillDirectoryRelativePaths: [String]?
    /// Explicit environment values for a bundled stdio MCP server.
    public var launchEnvironment: [String: String]?
    /// Parent-process environment names a bundled server explicitly requests.
    public var inheritedEnvironmentVariableNames: [String]?
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
        serverURL: String? = nil,
        headers: [String: String]? = nil,
        oauthClientID: String? = nil,
        launchExecutable: String? = nil,
        launchCommand: String? = nil,
        launchArguments: [String]? = nil,
        packageRootRelativePath: String? = nil,
        skillDirectoryRelativePaths: [String]? = nil,
        launchEnvironment: [String: String]? = nil,
        inheritedEnvironmentVariableNames: [String]? = nil,
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
        self.serverURL = serverURL
        self.headers = headers
        self.oauthClientID = oauthClientID
        self.launchExecutable = launchExecutable
        self.launchCommand = launchCommand
        self.launchArguments = launchArguments
        self.packageRootRelativePath = packageRootRelativePath
        self.skillDirectoryRelativePaths = skillDirectoryRelativePaths
        self.launchEnvironment = launchEnvironment
        self.inheritedEnvironmentVariableNames = inheritedEnvironmentVariableNames
        self.installCommand = installCommand
        self.installTimeoutSeconds = installTimeoutSeconds
        self.updateCommand = updateCommand
        self.updateTimeoutSeconds = updateTimeoutSeconds
    }
}
