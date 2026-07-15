import Foundation

public struct MCPServerProbeResult: Sendable, Hashable {
    public var protocolVersion: String?
    public var serverName: String?
    public var serverVersion: String?
    public var serverInfo: MCPJSONValue?
    public var tools: [MCPJSONValue]
    public var resources: [MCPJSONValue]
    public var resourceTemplates: [MCPJSONValue]
    public var toolDescriptors: [MCPToolDescriptor]
    public var toolNames: [String]
    public var resourceNames: [String]
    public var resourceURIs: [String]
    public var promptNames: [String]

    public init(
        protocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        serverInfo: MCPJSONValue? = nil,
        tools: [MCPJSONValue] = [],
        resources: [MCPJSONValue] = [],
        resourceTemplates: [MCPJSONValue] = [],
        toolDescriptors: [MCPToolDescriptor] = [],
        toolNames: [String] = [],
        resourceNames: [String] = [],
        resourceURIs: [String] = [],
        promptNames: [String] = []
    ) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.serverInfo = serverInfo
        self.tools = tools
        self.resources = resources
        self.resourceTemplates = resourceTemplates
        self.toolDescriptors = toolDescriptors.isEmpty
            ? toolNames.map { MCPToolDescriptor(name: $0) }
            : toolDescriptors
        self.toolNames = toolNames.isEmpty
            ? self.toolDescriptors.map(\.name)
            : toolNames
        self.resourceNames = resourceNames
        self.resourceURIs = resourceURIs
        self.promptNames = promptNames
    }
}

public enum MCPProbeDetail: String, Sendable, Hashable {
    case full
    case toolsAndAuthOnly
}

public struct MCPToolCallResult: Codable, Sendable, Hashable {
    public var content: [MCPJSONValue]
    public var structuredContent: MCPJSONValue?
    public var isError: Bool?
    public var metadata: MCPJSONValue?

    public init(
        content: [MCPJSONValue] = [],
        structuredContent: MCPJSONValue? = nil,
        isError: Bool? = nil,
        metadata: MCPJSONValue? = nil
    ) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
        self.metadata = metadata
    }
}

public struct MCPResourceReadResult: Codable, Sendable, Hashable {
    public var contents: [MCPJSONValue]

    public init(contents: [MCPJSONValue] = []) {
        self.contents = contents
    }
}

public struct MCPToolDescriptor: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var requiredArguments: [String]
    public var optionalArguments: [String]
    public var schemaSummary: String

    public init(
        name: String,
        description: String = "",
        requiredArguments: [String] = [],
        optionalArguments: [String] = [],
        schemaSummary: String = ""
    ) {
        self.name = name
        self.description = description
        self.requiredArguments = requiredArguments
        self.optionalArguments = optionalArguments
        self.schemaSummary = schemaSummary
    }
}

public enum MCPProbeError: LocalizedError, Equatable {
    case invalidMessage(String)
    case responseError(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMessage(let message):
            return message
        case .responseError(let message):
            return message
        case .timeout(let message):
            return message
        }
    }
}
