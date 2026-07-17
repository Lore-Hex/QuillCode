import Foundation

public enum ExternalAgentConfigItemType: String, Codable, Sendable, Hashable, CaseIterable {
    case agentsMD = "AGENTS_MD"
    case config = "CONFIG"
    case skills = "SKILLS"
    case plugins = "PLUGINS"
    case mcpServerConfig = "MCP_SERVER_CONFIG"
    case subagents = "SUBAGENTS"
    case hooks = "HOOKS"
    case commands = "COMMANDS"
    case sessions = "SESSIONS"

    /// Codex groups completed import results in service execution order rather than request order.
    public static let importOrder: [Self] = [
        .config,
        .skills,
        .agentsMD,
        .plugins,
        .mcpServerConfig,
        .subagents,
        .hooks,
        .commands,
        .sessions,
    ]
}

public struct ExternalAgentConfigNamedMigration: Codable, Sendable, Hashable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ExternalAgentConfigPluginsMigration: Codable, Sendable, Hashable {
    public var marketplaceName: String
    public var pluginNames: [String]

    public init(marketplaceName: String, pluginNames: [String]) {
        self.marketplaceName = marketplaceName
        self.pluginNames = pluginNames
    }
}

public struct ExternalAgentConfigSessionMigration: Codable, Sendable, Hashable {
    public var path: String
    public var cwd: String
    public var title: String?

    public init(path: String, cwd: String, title: String? = nil) {
        self.path = path
        self.cwd = cwd
        self.title = title
    }
}

public struct ExternalAgentConfigMigrationDetails: Codable, Sendable, Hashable {
    public var plugins: [ExternalAgentConfigPluginsMigration]
    public var sessions: [ExternalAgentConfigSessionMigration]
    public var mcpServers: [ExternalAgentConfigNamedMigration]
    public var hooks: [ExternalAgentConfigNamedMigration]
    public var subagents: [ExternalAgentConfigNamedMigration]
    public var commands: [ExternalAgentConfigNamedMigration]

    public init(
        plugins: [ExternalAgentConfigPluginsMigration] = [],
        sessions: [ExternalAgentConfigSessionMigration] = [],
        mcpServers: [ExternalAgentConfigNamedMigration] = [],
        hooks: [ExternalAgentConfigNamedMigration] = [],
        subagents: [ExternalAgentConfigNamedMigration] = [],
        commands: [ExternalAgentConfigNamedMigration] = []
    ) {
        self.plugins = plugins
        self.sessions = sessions
        self.mcpServers = mcpServers
        self.hooks = hooks
        self.subagents = subagents
        self.commands = commands
    }
}

public struct ExternalAgentConfigMigrationItem: Codable, Sendable, Hashable {
    public var itemType: ExternalAgentConfigItemType
    public var description: String
    public var cwd: String?
    public var details: ExternalAgentConfigMigrationDetails?

    public init(
        itemType: ExternalAgentConfigItemType,
        description: String,
        cwd: String? = nil,
        details: ExternalAgentConfigMigrationDetails? = nil
    ) {
        self.itemType = itemType
        self.description = description
        self.cwd = cwd
        self.details = details
    }
}

public struct ExternalAgentConfigImportSuccess: Codable, Sendable, Hashable {
    public var itemType: ExternalAgentConfigItemType
    public var cwd: String?
    public var source: String?
    public var target: String?

    public init(
        itemType: ExternalAgentConfigItemType,
        cwd: String? = nil,
        source: String? = nil,
        target: String? = nil
    ) {
        self.itemType = itemType
        self.cwd = cwd
        self.source = source
        self.target = target
    }
}

public struct ExternalAgentConfigImportFailure: Codable, Sendable, Hashable {
    public var itemType: ExternalAgentConfigItemType
    public var cwd: String?
    public var source: String?
    public var errorType: String?
    public var failureStage: String
    public var message: String

    public init(
        itemType: ExternalAgentConfigItemType,
        cwd: String? = nil,
        source: String? = nil,
        errorType: String? = nil,
        failureStage: String,
        message: String
    ) {
        self.itemType = itemType
        self.cwd = cwd
        self.source = source
        self.errorType = errorType
        self.failureStage = failureStage
        self.message = message
    }
}

public struct ExternalAgentConfigImportTypeResult: Codable, Sendable, Hashable {
    public var itemType: ExternalAgentConfigItemType
    public var successes: [ExternalAgentConfigImportSuccess]
    public var failures: [ExternalAgentConfigImportFailure]

    public init(
        itemType: ExternalAgentConfigItemType,
        successes: [ExternalAgentConfigImportSuccess] = [],
        failures: [ExternalAgentConfigImportFailure] = []
    ) {
        self.itemType = itemType
        self.successes = successes
        self.failures = failures
    }
}

public struct ExternalAgentConfigImportHistory: Codable, Sendable, Hashable {
    public var importId: UUID
    public var completedAtMs: Int64
    public var successes: [ExternalAgentConfigImportSuccess]
    public var failures: [ExternalAgentConfigImportFailure]

    public init(
        importId: UUID,
        completedAtMs: Int64,
        successes: [ExternalAgentConfigImportSuccess],
        failures: [ExternalAgentConfigImportFailure]
    ) {
        self.importId = importId
        self.completedAtMs = completedAtMs
        self.successes = successes
        self.failures = failures
    }
}
