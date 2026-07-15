import Foundation
import QuillCodeCore

/// Raw tools advertised by one initialized MCP server.
public struct MCPAgentServerTools: Sendable, Hashable {
    public let serverName: String
    public let tools: [MCPJSONValue]

    public init(serverName: String, tools: [MCPJSONValue]) {
        self.serverName = serverName
        self.tools = tools
    }
}

/// Maps a bounded model-visible tool name back to the exact MCP wire identity.
public struct MCPAgentToolRoute: Sendable, Hashable {
    public let modelName: String
    public let serverName: String
    public let toolName: String

    public init(modelName: String, serverName: String, toolName: String) {
        self.modelName = modelName
        self.serverName = serverName
        self.toolName = toolName
    }
}

/// Converts raw MCP tool inventories into deterministic agent schemas and execution routes.
///
/// MCP permits names that model tool APIs do not. The catalog therefore exposes a stable
/// `mcp__server__tool` alias while retaining exact server/tool names for transport calls.
public struct MCPAgentToolCatalog: Sendable {
    public static let maximumModelNameBytes = 64

    public let definitions: [ToolDefinition]
    public let routesByModelName: [String: MCPAgentToolRoute]

    public init(servers: [MCPAgentServerTools]) {
        let tools = Self.rawTools(from: servers)
        let aliases = Self.aliases(for: tools)
        var definitions: [ToolDefinition] = []
        var routes: [String: MCPAgentToolRoute] = [:]
        definitions.reserveCapacity(tools.count)
        routes.reserveCapacity(tools.count)

        for tool in tools {
            guard let modelName = aliases[tool.identity] else { continue }
            definitions.append(ToolDefinition(
                name: modelName,
                description: tool.description,
                parametersJSON: tool.parametersJSON,
                host: .mcp,
                risk: tool.risk
            ))
            routes[modelName] = MCPAgentToolRoute(
                modelName: modelName,
                serverName: tool.identity.serverName,
                toolName: tool.identity.toolName
            )
        }

        self.definitions = definitions
        self.routesByModelName = routes
    }

    public func route(forModelName name: String) -> MCPAgentToolRoute? {
        routesByModelName[name]
    }
}

private extension MCPAgentToolCatalog {
    struct Identity: Sendable, Hashable, Comparable {
        let serverName: String
        let toolName: String

        static func < (lhs: Identity, rhs: Identity) -> Bool {
            if lhs.serverName != rhs.serverName { return lhs.serverName < rhs.serverName }
            return lhs.toolName < rhs.toolName
        }
    }

    struct RawTool: Sendable {
        let identity: Identity
        let description: String
        let parametersJSON: String
        let risk: ToolRiskClass
        let unboundedAlias: String
    }

    static let emptyObjectSchema = #"{"properties":{},"type":"object"}"#

    static func rawTools(from servers: [MCPAgentServerTools]) -> [RawTool] {
        var byIdentity: [Identity: RawTool] = [:]
        for server in servers.sorted(by: { $0.serverName < $1.serverName }) {
            for value in server.tools {
                guard let object = value.objectValue,
                      let rawName = nonEmpty(object["name"]?.stringValue)
                else { continue }
                let identity = Identity(serverName: server.serverName, toolName: rawName)
                guard byIdentity[identity] == nil else { continue }
                let rawDescription = nonEmpty(object["description"]?.stringValue)
                let description = rawDescription
                    ?? "MCP tool \(rawName) from \(server.serverName)."
                let schema = object["inputSchema"] ?? object["input_schema"]
                byIdentity[identity] = RawTool(
                    identity: identity,
                    description: description,
                    parametersJSON: encodedObject(schema) ?? emptyObjectSchema,
                    risk: risk(from: object["annotations"]),
                    unboundedAlias: "mcp__\(sanitize(server.serverName))__\(sanitize(rawName))"
                )
            }
        }
        return byIdentity.values.sorted { $0.identity < $1.identity }
    }

    static func aliases(for tools: [RawTool]) -> [Identity: String] {
        let groups = Dictionary(grouping: tools, by: \.unboundedAlias)
        var aliases: [Identity: String] = [:]
        var used = Set<String>()

        for tool in tools {
            let needsHash = tool.unboundedAlias.utf8.count > maximumModelNameBytes
                || (groups[tool.unboundedAlias]?.count ?? 0) > 1
            let suffix = needsHash ? "__\(digest(tool.identity))" : ""
            let prefixLimit = maximumModelNameBytes - suffix.utf8.count
            var candidate = String(tool.unboundedAlias.prefix(prefixLimit)) + suffix
            var sequence = 2
            while !used.insert(candidate).inserted {
                let collisionSuffix = "__\(digest(tool.identity))_\(sequence)"
                candidate = String(tool.unboundedAlias.prefix(maximumModelNameBytes - collisionSuffix.utf8.count))
                    + collisionSuffix
                sequence += 1
            }
            aliases[tool.identity] = candidate
        }
        return aliases
    }

    static func sanitize(_ name: String) -> String {
        let scalars = name.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            let isASCIIAlphaNumeric = (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
            return isASCIIAlphaNumeric || value == 95 ? Character(String(scalar)) : "_"
        }
        let result = String(scalars)
        return result.isEmpty ? "_" : result
    }

    static func digest(_ identity: Identity) -> String {
        MCPCrypto.sha256(Array("\(identity.serverName)\u{0}\(identity.toolName)".utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func encodedObject(_ value: MCPJSONValue?) -> String? {
        guard let value, value.objectValue != nil else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              data.count <= MCPJSONValue.maximumEncodedBytes
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func risk(from annotations: MCPJSONValue?) -> ToolRiskClass {
        guard let annotations = annotations?.objectValue else { return .append }
        if boolean(annotations["destructiveHint"]) == true { return .destructive }
        if boolean(annotations["readOnlyHint"]) == true { return .read }
        return .append
    }

    static func boolean(_ value: MCPJSONValue?) -> Bool? {
        guard case .bool(let result) = value else { return nil }
        return result
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
