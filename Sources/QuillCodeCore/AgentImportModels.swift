import Foundation

public enum AgentImportSource: String, Codable, Sendable, Hashable, CaseIterable {
    case claudeCode = "claude-code"

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        }
    }
}

public enum AgentImportItemKind: String, Codable, Sendable, Hashable, CaseIterable {
    case instructions
    case settings
    case skills
    case plugins
    case projects
    case chats
    case mcpServers = "mcp-servers"
    case hooks
    case slashCommands = "slash-commands"
    case subagents

    public var displayName: String {
        switch self {
        case .instructions: "Instructions"
        case .settings: "Settings"
        case .skills: "Skills"
        case .plugins: "Plugins"
        case .projects: "Projects"
        case .chats: "Recent chats"
        case .mcpServers: "MCP servers"
        case .hooks: "Hooks"
        case .slashCommands: "Slash commands"
        case .subagents: "Subagents"
        }
    }

    public var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}

public struct AgentImportProject: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isAlreadyRegistered: Bool

    public init(name: String, path: String, isAlreadyRegistered: Bool) {
        self.name = name
        self.path = path
        self.isAlreadyRegistered = isAlreadyRegistered
    }
}

public struct AgentImportCandidate: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: AgentImportItemKind
    public var title: String
    public var detail: String
    public var projectPath: String?
    public var requiresSetup: Bool
    public var isPreviouslyImported: Bool

    public init(
        id: String,
        kind: AgentImportItemKind,
        title: String,
        detail: String,
        projectPath: String? = nil,
        requiresSetup: Bool = false,
        isPreviouslyImported: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.projectPath = projectPath
        self.requiresSetup = requiresSetup
        self.isPreviouslyImported = isPreviouslyImported
    }
}

public struct AgentImportPreview: Codable, Sendable, Hashable {
    public var source: AgentImportSource
    public var projects: [AgentImportProject]
    public var candidates: [AgentImportCandidate]
    public var diagnostics: [String]

    public init(
        source: AgentImportSource,
        projects: [AgentImportProject] = [],
        candidates: [AgentImportCandidate] = [],
        diagnostics: [String] = []
    ) {
        self.source = source
        self.projects = projects
        self.candidates = candidates
        self.diagnostics = diagnostics
    }

    public var selectableCandidates: [AgentImportCandidate] {
        candidates.filter { !$0.isPreviouslyImported }
    }

    public var defaultCandidateIDs: Set<String> {
        Set(selectableCandidates.map(\.id))
    }

    public var defaultProjectPaths: Set<String> {
        Set(projects.map(\.path))
    }

    public var alreadyImportedCount: Int {
        candidates.lazy.filter(\.isPreviouslyImported).count
    }
}

public struct AgentImportSelection: Codable, Sendable, Hashable {
    public var source: AgentImportSource
    public var candidateIDs: Set<String>
    public var projectPaths: Set<String>

    public init(
        source: AgentImportSource,
        candidateIDs: Set<String>,
        projectPaths: Set<String>
    ) {
        self.source = source
        self.candidateIDs = candidateIDs
        self.projectPaths = projectPaths
    }
}

public struct AgentImportCount: Codable, Sendable, Hashable, Identifiable {
    public var id: AgentImportItemKind { kind }
    public var kind: AgentImportItemKind
    public var count: Int

    public init(kind: AgentImportItemKind, count: Int) {
        self.kind = kind
        self.count = max(0, count)
    }
}

public struct AgentImportOutcome: Codable, Sendable, Hashable {
    public var source: AgentImportSource
    public var imported: [AgentImportCount]
    public var skippedCount: Int
    public var setupFollowUps: [String]
    public var diagnostics: [String]

    public init(
        source: AgentImportSource,
        imported: [AgentImportCount] = [],
        skippedCount: Int = 0,
        setupFollowUps: [String] = [],
        diagnostics: [String] = []
    ) {
        self.source = source
        self.imported = imported
            .filter { $0.count > 0 }
            .sorted { $0.kind.sortOrder < $1.kind.sortOrder }
        self.skippedCount = max(0, skippedCount)
        self.setupFollowUps = setupFollowUps
        self.diagnostics = diagnostics
    }

    public var importedCount: Int {
        imported.reduce(0) { $0 + $1.count }
    }
}

public struct AgentImportMutation: Sendable, Hashable {
    public var projects: [ProjectRef]
    public var threads: [ChatThread]
    public var createdArtifacts: [AgentImportCreatedArtifact]
    public var importedCandidateIDs: Set<String>
    public var outcome: AgentImportOutcome

    public init(
        projects: [ProjectRef] = [],
        threads: [ChatThread] = [],
        createdArtifacts: [AgentImportCreatedArtifact] = [],
        importedCandidateIDs: Set<String> = [],
        outcome: AgentImportOutcome
    ) {
        self.projects = projects
        self.threads = threads
        self.createdArtifacts = createdArtifacts
        self.importedCandidateIDs = importedCandidateIDs
        self.outcome = outcome
    }
}

public struct AgentImportCreatedArtifact: Sendable, Hashable {
    public var projectRootPath: String
    public var path: String

    public init(projectRootPath: String, path: String) {
        self.projectRootPath = projectRootPath
        self.path = path
    }
}

public struct AgentImportThreadProvenance: Codable, Sendable, Hashable {
    public static let payloadKey = "agentImport"

    public var source: AgentImportSource
    public var sourceID: String

    public init(source: AgentImportSource, sourceID: String) {
        self.source = source
        self.sourceID = sourceID
    }

    public static func value(in thread: ChatThread) -> AgentImportThreadProvenance? {
        for event in thread.events where event.kind == .notice {
            guard let payload = event.payloadJSON?.data(using: .utf8),
                  let wrapper = try? JSONDecoder().decode(
                    [String: AgentImportThreadProvenance].self,
                    from: payload
                  ),
                  let provenance = wrapper[payloadKey]
            else { continue }
            return provenance
        }
        return nil
    }
}
