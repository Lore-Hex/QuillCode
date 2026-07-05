import Foundation

public struct ProjectRef: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String
    public var connection: ProjectConnection
    public var instructions: [ProjectInstruction]
    public var instructionDiagnosticResolutions: [ProjectInstructionDiagnosticResolution]
    public var localActions: [LocalEnvironmentAction]
    public var runHooks: [ProjectRunHook]
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
        runHooks: [ProjectRunHook],
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
        self.runHooks = runHooks
        self.extensionManifests = extensionManifests
        self.memories = memories
        self.lastOpenedAt = lastOpenedAt
    }

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
        self.init(
            id: id,
            name: name,
            path: path,
            connection: connection,
            lastOpenedAt: lastOpenedAt,
            instructions: instructions,
            instructionDiagnosticResolutions: instructionDiagnosticResolutions,
            localActions: localActions,
            runHooks: [],
            extensionManifests: extensionManifests,
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
        case runHooks
        case extensionManifests
        case memories
        case lastOpenedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.connection = try container.decodeIfPresent(
            ProjectConnection.self,
            forKey: .connection
        ) ?? .local(path: path)
        self.instructions = try container.decodeIfPresent([ProjectInstruction].self, forKey: .instructions) ?? []
        self.instructionDiagnosticResolutions = Self.normalizedInstructionDiagnosticResolutions(
            try container.decodeIfPresent(
                [ProjectInstructionDiagnosticResolution].self,
                forKey: .instructionDiagnosticResolutions
            ) ?? []
        )
        self.localActions = try container.decodeIfPresent([LocalEnvironmentAction].self, forKey: .localActions) ?? []
        self.runHooks = try container.decodeIfPresent([ProjectRunHook].self, forKey: .runHooks) ?? []
        self.extensionManifests = try container.decodeIfPresent(
            [ProjectExtensionManifest].self,
            forKey: .extensionManifests
        ) ?? []
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
        try container.encode(runHooks, forKey: .runHooks)
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
