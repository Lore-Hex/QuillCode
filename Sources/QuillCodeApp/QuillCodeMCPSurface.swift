import Foundation
import QuillCodeTools

public struct ExtensionsState: Sendable, Hashable {
    public var isVisible: Bool
    public var mcpServerStatuses: [String: MCPServerLifecycleStatus]
    public var mcpServerProbeSummaries: [String: MCPServerProbeSummary]

    public init(
        isVisible: Bool = false,
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        mcpServerProbeSummaries: [String: MCPServerProbeSummary] = [:]
    ) {
        self.isVisible = isVisible
        self.mcpServerStatuses = mcpServerStatuses
        self.mcpServerProbeSummaries = mcpServerProbeSummaries
    }
}

public enum MCPServerLifecycleStatus: String, Sendable, Hashable {
    case stopped
    case probing
    case running
    case ready
    case failed

    public var title: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .probing:
            return "Probing"
        case .running:
            return "Running"
        case .ready:
            return "Ready"
        case .failed:
            return "Failed"
        }
    }

    public var isActive: Bool {
        switch self {
        case .probing, .running, .ready:
            return true
        case .stopped, .failed:
            return false
        }
    }
}

public struct MCPServerProbeSummary: Codable, Sendable, Hashable {
    public var protocolVersion: String?
    public var serverName: String?
    public var serverVersion: String?
    public var toolDescriptors: [MCPToolDescriptor]
    public var toolNames: [String]
    public var resourceNames: [String]
    public var resourceURIs: [String]
    public var promptNames: [String]
    public var errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case serverName
        case serverVersion
        case toolDescriptors
        case toolNames
        case resourceNames
        case resourceURIs
        case promptNames
        case errorMessage
    }

    public init(
        protocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        toolDescriptors: [MCPToolDescriptor] = [],
        toolNames: [String] = [],
        resourceNames: [String] = [],
        resourceURIs: [String] = [],
        promptNames: [String] = [],
        errorMessage: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.toolDescriptors = toolDescriptors.isEmpty
            ? toolNames.map { MCPToolDescriptor(name: $0) }
            : toolDescriptors
        self.toolNames = toolNames.isEmpty
            ? self.toolDescriptors.map(\.name)
            : toolNames
        self.resourceNames = resourceNames
        self.resourceURIs = resourceURIs
        self.promptNames = promptNames
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
        self.serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
        self.serverVersion = try container.decodeIfPresent(String.self, forKey: .serverVersion)
        self.toolDescriptors = try container.decodeIfPresent([MCPToolDescriptor].self, forKey: .toolDescriptors) ?? []
        self.toolNames = try container.decodeIfPresent([String].self, forKey: .toolNames) ?? []
        if self.toolDescriptors.isEmpty {
            self.toolDescriptors = self.toolNames.map { MCPToolDescriptor(name: $0) }
        }
        if self.toolNames.isEmpty {
            self.toolNames = self.toolDescriptors.map(\.name)
        }
        self.resourceNames = try container.decodeIfPresent([String].self, forKey: .resourceNames) ?? []
        self.resourceURIs = try container.decodeIfPresent([String].self, forKey: .resourceURIs) ?? []
        self.promptNames = try container.decodeIfPresent([String].self, forKey: .promptNames) ?? []
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }

    public init(result: MCPServerProbeResult) {
        self.init(
            protocolVersion: result.protocolVersion,
            serverName: result.serverName,
            serverVersion: result.serverVersion,
            toolDescriptors: result.toolDescriptors,
            resourceNames: result.resourceNames,
            resourceURIs: result.resourceURIs,
            promptNames: result.promptNames,
            errorMessage: nil
        )
    }

    public var serverLabel: String? {
        switch (serverName, serverVersion) {
        case let (.some(name), .some(version)) where !version.isEmpty:
            return "\(name) \(version)"
        case let (.some(name), _):
            return name
        default:
            return nil
        }
    }

    public var toolCountLabel: String? {
        guard errorMessage == nil else { return nil }
        return "\(toolNames.count) tool\(toolNames.count == 1 ? "" : "s")"
    }

    public var resourceCountLabel: String? {
        guard errorMessage == nil, !resourceNames.isEmpty else { return nil }
        return "\(resourceNames.count) resource\(resourceNames.count == 1 ? "" : "s")"
    }

    public var promptCountLabel: String? {
        guard errorMessage == nil, !promptNames.isEmpty else { return nil }
        return "\(promptNames.count) prompt\(promptNames.count == 1 ? "" : "s")"
    }
}

public struct MCPReferenceActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { commandID }

    public var title: String
    public var detail: String?
    public var commandID: String

    public init(title: String, detail: String? = nil, commandID: String) {
        self.title = title
        self.detail = detail
        self.commandID = commandID
    }
}
