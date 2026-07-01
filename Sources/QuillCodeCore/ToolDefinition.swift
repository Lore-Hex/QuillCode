import Foundation

public enum ToolHost: String, Codable, Sendable {
    case local
    case browser
    case computer
    case plugin
    case mcp
}

public enum ToolRiskClass: String, Codable, Sendable {
    case read
    case append
    case destructive
}

public struct ToolDefinition: Codable, Sendable, Hashable {
    public var name: String
    public var description: String
    public var parametersJSON: String
    public var host: ToolHost
    public var risk: ToolRiskClass

    public init(
        name: String,
        description: String,
        parametersJSON: String,
        host: ToolHost = .local,
        risk: ToolRiskClass = .read
    ) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
        self.host = host
        self.risk = risk
    }
}
