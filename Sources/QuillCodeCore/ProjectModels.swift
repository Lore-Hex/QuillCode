import Foundation

public enum ProjectConnectionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case local
    case ssh
}

public struct ProjectConnection: Codable, Sendable, Hashable {
    public var kind: ProjectConnectionKind
    public var path: String
    public var host: String?
    public var user: String?
    public var port: Int?

    public init(
        kind: ProjectConnectionKind,
        path: String,
        host: String? = nil,
        user: String? = nil,
        port: Int? = nil
    ) {
        self.kind = kind
        self.path = path
        self.host = host
        self.user = user
        self.port = port
    }

    public static func local(path: String) -> ProjectConnection {
        ProjectConnection(kind: .local, path: path)
    }

    public static func ssh(path: String, host: String, user: String? = nil, port: Int? = nil) -> ProjectConnection {
        ProjectConnection(kind: .ssh, path: path, host: host, user: user, port: port)
    }

    public static func parseSSH(_ value: String) -> ProjectConnection? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed),
           components.scheme == "ssh",
           let host = components.host,
           !host.isEmpty {
            let path = components.path.isEmpty ? "/" : components.path
            return .ssh(path: path, host: host, user: components.user, port: components.port)
        }

        guard let separatorIndex = trimmed.firstIndex(of: ":") else { return nil }
        let left = String(trimmed[..<separatorIndex])
        let path = String(trimmed[trimmed.index(after: separatorIndex)...])
        guard !left.isEmpty, path.hasPrefix("/") || path.hasPrefix("~") else { return nil }

        let userAndHost = left.split(separator: "@", maxSplits: 1).map(String.init)
        let user = userAndHost.count == 2 ? userAndHost[0] : nil
        let host = userAndHost.count == 2 ? userAndHost[1] : userAndHost[0]
        guard !host.isEmpty else { return nil }
        return .ssh(path: path, host: host, user: user)
    }

    public var isRemote: Bool {
        kind != .local
    }

    public var displayLabel: String {
        switch kind {
        case .local:
            return path
        case .ssh:
            let userPrefix = user.map { "\($0)@" } ?? ""
            let hostLabel = host ?? "ssh"
            let portSuffix = port.map { ":\($0)" } ?? ""
            return "ssh://\(userPrefix)\(hostLabel)\(portSuffix)\(path)"
        }
    }

    public var kindLabel: String {
        switch kind {
        case .local:
            return "Local"
        case .ssh:
            return "SSH Remote"
        }
    }
}

public struct ProjectRef: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String
    public var connection: ProjectConnection
    public var instructions: [ProjectInstruction]
    public var instructionDiagnosticResolutions: [ProjectInstructionDiagnosticResolution]
    public var localActions: [LocalEnvironmentAction]
    public var extensionManifests: [ProjectExtensionManifest]
    public var memories: [MemoryNote]
    public var lastOpenedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        connection: ProjectConnection? = nil,
        lastOpenedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        instructionDiagnosticResolutions: [ProjectInstructionDiagnosticResolution] = [],
        localActions: [LocalEnvironmentAction] = [],
        extensionManifests: [ProjectExtensionManifest] = [],
        memories: [MemoryNote] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.connection = connection ?? .local(path: path)
        self.instructions = instructions
        self.instructionDiagnosticResolutions = Self.normalizedInstructionDiagnosticResolutions(
            instructionDiagnosticResolutions
        )
        self.localActions = localActions
        self.extensionManifests = extensionManifests
        self.memories = memories
        self.lastOpenedAt = lastOpenedAt
    }

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        lastOpenedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        instructionDiagnosticResolutions: [ProjectInstructionDiagnosticResolution] = [],
        localActions: [LocalEnvironmentAction] = []
    ) {
        self.init(
            id: id,
            name: name,
            path: path,
            lastOpenedAt: lastOpenedAt,
            instructions: instructions,
            instructionDiagnosticResolutions: instructionDiagnosticResolutions,
            localActions: localActions,
            extensionManifests: [],
            memories: []
        )
    }

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        lastOpenedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        instructionDiagnosticResolutions: [ProjectInstructionDiagnosticResolution] = [],
        localActions: [LocalEnvironmentAction] = [],
        memories: [MemoryNote]
    ) {
        self.init(
            id: id,
            name: name,
            path: path,
            lastOpenedAt: lastOpenedAt,
            instructions: instructions,
            instructionDiagnosticResolutions: instructionDiagnosticResolutions,
            localActions: localActions,
            extensionManifests: [],
            memories: memories
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case connection
        case instructions
        case instructionDiagnosticResolutions
        case localActions
        case extensionManifests
        case memories
        case lastOpenedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.connection = try container.decodeIfPresent(ProjectConnection.self, forKey: .connection) ?? .local(path: path)
        self.instructions = try container.decodeIfPresent([ProjectInstruction].self, forKey: .instructions) ?? []
        self.instructionDiagnosticResolutions = Self.normalizedInstructionDiagnosticResolutions(
            try container.decodeIfPresent(
                [ProjectInstructionDiagnosticResolution].self,
                forKey: .instructionDiagnosticResolutions
            ) ?? []
        )
        self.localActions = try container.decodeIfPresent([LocalEnvironmentAction].self, forKey: .localActions) ?? []
        self.extensionManifests = try container.decodeIfPresent([ProjectExtensionManifest].self, forKey: .extensionManifests) ?? []
        self.memories = try container.decodeIfPresent([MemoryNote].self, forKey: .memories) ?? []
        self.lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(connection, forKey: .connection)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(instructionDiagnosticResolutions, forKey: .instructionDiagnosticResolutions)
        try container.encode(localActions, forKey: .localActions)
        try container.encode(extensionManifests, forKey: .extensionManifests)
        try container.encode(memories, forKey: .memories)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
    }

    public var isRemote: Bool {
        connection.isRemote
    }

    public var displayPath: String {
        connection.displayLabel
    }

}

public struct ProjectInstruction: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var scopePath: String
    public var title: String
    public var content: String
    public var byteCount: Int
    public var wasTruncated: Bool

    public init(
        path: String,
        scopePath: String? = nil,
        title: String,
        content: String,
        byteCount: Int,
        wasTruncated: Bool = false
    ) {
        self.path = path
        self.scopePath = scopePath ?? Self.scopePath(for: path)
        self.title = title
        self.content = content
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
    }

    public var scopeLabel: String {
        Self.scopeLabel(for: scopePath)
    }

    public static func scopeLabel(for scopePath: String) -> String {
        scopePath == "." ? "whole project" : "\(scopePath)/**"
    }

    public static func scopePath(for instructionPath: String) -> String {
        let components = instructionPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.count > 1 else { return "." }

        let suffix = Array(components.suffix(2))
        if suffix == [".quillcode", "rules.md"]
            || suffix == [".quillcode", "instructions.md"] {
            let scope = components.dropLast(2).joined(separator: "/")
            return scope.isEmpty ? "." : scope
        }

        let scope = components.dropLast().joined(separator: "/")
        return scope.isEmpty ? "." : scope
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case scopePath
        case title
        case content
        case byteCount
        case wasTruncated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.scopePath = try container.decodeIfPresent(String.self, forKey: .scopePath)
            ?? Self.scopePath(for: path)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.byteCount = try container.decode(Int.self, forKey: .byteCount)
        self.wasTruncated = try container.decodeIfPresent(Bool.self, forKey: .wasTruncated) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(scopePath, forKey: .scopePath)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encode(wasTruncated, forKey: .wasTruncated)
    }
}

public struct LocalEnvironmentAction: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String?
    public var relativePath: String
    public var command: String
    public var sortOrder: Int?
    public var environment: [String: String]?
    public var workingDirectory: String?
    public var timeoutSeconds: Int?

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        relativePath: String,
        command: String,
        sortOrder: Int? = nil,
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeoutSeconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.relativePath = relativePath
        self.command = command
        self.sortOrder = sortOrder
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
    }
}

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
