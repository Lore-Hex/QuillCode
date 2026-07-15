import Foundation

/// A bounded, concurrency-safe JSON value used at MCP wire boundaries.
///
/// MCP deliberately allows extension fields in tool schemas, content blocks, and metadata. Keeping
/// those values wire-shaped avoids dropping data when QuillCode projects MCP through app-server.
public enum MCPJSONValue: Codable, Sendable, Hashable {
    case object([String: MCPJSONValue])
    case array([MCPJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public static let maximumEncodedBytes = MCPStdioMessageCodec.maxMessageBytes

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self), value.isFinite {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: MCPJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public init(jsonObject: Any) throws {
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw MCPProbeError.invalidMessage("MCP returned an invalid JSON value.")
        }
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
        guard data.count <= Self.maximumEncodedBytes else {
            throw MCPProbeError.invalidMessage("MCP JSON exceeded the transport size limit.")
        }
        self = try JSONDecoder().decode(MCPJSONValue.self, from: data)
    }

    public init(jsonData: Data) throws {
        guard jsonData.count <= Self.maximumEncodedBytes else {
            throw MCPProbeError.invalidMessage("MCP JSON exceeded the transport size limit.")
        }
        self = try JSONDecoder().decode(MCPJSONValue.self, from: jsonData)
    }

    public var objectValue: [String: MCPJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [MCPJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var foundationObject: Any {
        switch self {
        case .object(let value): value.mapValues(\.foundationObject)
        case .array(let value): value.map(\.foundationObject)
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        }
    }
}
