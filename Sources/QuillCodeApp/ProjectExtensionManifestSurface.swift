import Foundation
import QuillCodeCore
import QuillCodeTools

public struct ProjectExtensionManifestSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ProjectExtensionKind
    public var kindLabel: String
    public var name: String
    public var summary: String
    public var versionLabel: String?
    public var sourceURL: String?
    public var relativePath: String
    public var statusLabel: String
    public var transportLabel: String?
    public var launchCommand: String?
    public var updateCommand: String?
    public var serverLabel: String?
    public var protocolLabel: String?
    public var toolCountLabel: String?
    public var toolDescriptors: [MCPToolDescriptor]
    public var toolNames: [String]
    public var resourceCountLabel: String?
    public var resourceNames: [String]
    public var promptCountLabel: String?
    public var promptNames: [String]
    public var probeError: String?
    public var canStart: Bool
    public var canStop: Bool
    public var canUpdate: Bool
    public var startCommandID: String?
    public var stopCommandID: String?
    public var updateCommandID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case kindLabel
        case name
        case summary
        case versionLabel
        case sourceURL
        case relativePath
        case statusLabel
        case transportLabel
        case launchCommand
        case updateCommand
        case serverLabel
        case protocolLabel
        case toolCountLabel
        case toolDescriptors
        case toolNames
        case resourceCountLabel
        case resourceNames
        case promptCountLabel
        case promptNames
        case probeError
        case canStart
        case canStop
        case canUpdate
        case startCommandID
        case stopCommandID
        case updateCommandID
    }

    public init(
        manifest: ProjectExtensionManifest,
        mcpServerStatus: MCPServerLifecycleStatus = .stopped,
        probeSummary: MCPServerProbeSummary? = nil
    ) {
        self.id = manifest.id
        self.kind = manifest.kind
        self.kindLabel = manifest.kind.title
        self.name = manifest.name
        self.summary = manifest.summary
        self.versionLabel = manifest.version.map { "v\($0)" }
        self.sourceURL = manifest.sourceURL
        self.relativePath = manifest.relativePath
        if manifest.isEnabled {
            if manifest.kind == .mcpServer {
                self.statusLabel = manifest.launchExecutable == nil ? "Missing command" : mcpServerStatus.title
            } else {
                self.statusLabel = "Discovered"
            }
        } else {
            self.statusLabel = "Disabled"
        }
        self.transportLabel = manifest.transport?.rawValue.uppercased()
        self.launchCommand = manifest.launchCommand
        self.updateCommand = manifest.updateCommand
        self.serverLabel = probeSummary?.serverLabel
        self.protocolLabel = probeSummary?.protocolVersion.map { "MCP \($0)" }
        self.toolCountLabel = probeSummary?.toolCountLabel
        let descriptors = Array((probeSummary?.toolDescriptors ?? []).prefix(4))
        self.toolDescriptors = descriptors
        self.toolNames = descriptors.isEmpty
            ? Array((probeSummary?.toolNames ?? []).prefix(4))
            : descriptors.map(\.name)
        self.resourceCountLabel = probeSummary?.resourceCountLabel
        self.resourceNames = Array((probeSummary?.resourceNames ?? []).prefix(4))
        self.promptCountLabel = probeSummary?.promptCountLabel
        self.promptNames = Array((probeSummary?.promptNames ?? []).prefix(4))
        self.probeError = probeSummary?.errorMessage
        self.canStart = manifest.kind == .mcpServer
            && manifest.isEnabled
            && manifest.launchExecutable != nil
            && !mcpServerStatus.isActive
        self.canStop = manifest.kind == .mcpServer && mcpServerStatus.isActive
        self.canUpdate = manifest.updateCommand != nil
        self.startCommandID = canStart ? "mcp-start:\(manifest.id)" : nil
        self.stopCommandID = canStop ? "mcp-stop:\(manifest.id)" : nil
        self.updateCommandID = canUpdate ? "extension-update:\(manifest.id)" : nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = try container.decode(ProjectExtensionKind.self, forKey: .kind)
        self.kindLabel = try container.decode(String.self, forKey: .kindLabel)
        self.name = try container.decode(String.self, forKey: .name)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.versionLabel = try container.decodeIfPresent(String.self, forKey: .versionLabel)
        self.sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        self.relativePath = try container.decode(String.self, forKey: .relativePath)
        self.statusLabel = try container.decode(String.self, forKey: .statusLabel)
        self.transportLabel = try container.decodeIfPresent(String.self, forKey: .transportLabel)
        self.launchCommand = try container.decodeIfPresent(String.self, forKey: .launchCommand)
        self.updateCommand = try container.decodeIfPresent(String.self, forKey: .updateCommand)
        self.serverLabel = try container.decodeIfPresent(String.self, forKey: .serverLabel)
        self.protocolLabel = try container.decodeIfPresent(String.self, forKey: .protocolLabel)
        self.toolCountLabel = try container.decodeIfPresent(String.self, forKey: .toolCountLabel)
        self.toolDescriptors = try container.decodeIfPresent([MCPToolDescriptor].self, forKey: .toolDescriptors) ?? []
        self.toolNames = try container.decodeIfPresent([String].self, forKey: .toolNames) ?? []
        if self.toolDescriptors.isEmpty {
            self.toolDescriptors = self.toolNames.map { MCPToolDescriptor(name: $0) }
        }
        if self.toolNames.isEmpty {
            self.toolNames = self.toolDescriptors.map(\.name)
        }
        self.resourceCountLabel = try container.decodeIfPresent(String.self, forKey: .resourceCountLabel)
        self.resourceNames = try container.decodeIfPresent([String].self, forKey: .resourceNames) ?? []
        self.promptCountLabel = try container.decodeIfPresent(String.self, forKey: .promptCountLabel)
        self.promptNames = try container.decodeIfPresent([String].self, forKey: .promptNames) ?? []
        self.probeError = try container.decodeIfPresent(String.self, forKey: .probeError)
        self.canStart = try container.decode(Bool.self, forKey: .canStart)
        self.canStop = try container.decode(Bool.self, forKey: .canStop)
        self.canUpdate = try container.decodeIfPresent(Bool.self, forKey: .canUpdate) ?? false
        self.startCommandID = try container.decodeIfPresent(String.self, forKey: .startCommandID)
        self.stopCommandID = try container.decodeIfPresent(String.self, forKey: .stopCommandID)
        self.updateCommandID = try container.decodeIfPresent(String.self, forKey: .updateCommandID)
    }
}
