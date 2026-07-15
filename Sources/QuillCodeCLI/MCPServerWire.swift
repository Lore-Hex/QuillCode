import Foundation

enum MCPServerRequestID: Codable, Sendable, Hashable {
    case string(String)
    case integer(Int64)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        }
    }
}

struct MCPServerRPCError: Codable, Error, Sendable, Equatable {
    var code: Int
    var message: String
    var data: CLIJSONValue?

    static let parseError = MCPServerRPCError(code: -32700, message: "Parse error")
    static let invalidRequest = MCPServerRPCError(code: -32600, message: "Invalid Request")
    static let notInitialized = MCPServerRPCError(code: -32002, message: "Server not initialized")

    static func methodNotFound(_ method: String) -> MCPServerRPCError {
        MCPServerRPCError(code: -32601, message: "Method not found: \(method)")
    }

    static func internalError(_ reason: String) -> MCPServerRPCError {
        MCPServerRPCError(code: -32603, message: reason)
    }
}

enum MCPServerInboundMessage: Sendable, Equatable {
    case request(id: MCPServerRequestID, method: String, params: CLIJSONValue)
    case notification(method: String, params: CLIJSONValue)
    case response(id: MCPServerRequestID, result: CLIJSONValue?, error: MCPServerRPCError?)

    init(data: Data) throws {
        let envelope = try JSONDecoder().decode(MCPServerInboundEnvelope.self, from: data)
        guard envelope.jsonrpc == "2.0" else { throw MCPServerWireError.invalidEnvelope }
        if let method = envelope.method {
            let params = envelope.params ?? .object([:])
            if let id = envelope.id {
                self = .request(id: id, method: method, params: params)
            } else {
                self = .notification(method: method, params: params)
            }
            return
        }
        if let id = envelope.id, envelope.result != nil || envelope.error != nil {
            self = .response(id: id, result: envelope.result, error: envelope.error)
            return
        }
        throw MCPServerWireError.invalidEnvelope
    }
}

private struct MCPServerInboundEnvelope: Decodable {
    var jsonrpc: String?
    var id: MCPServerRequestID?
    var method: String?
    var params: CLIJSONValue?
    var result: CLIJSONValue?
    var error: MCPServerRPCError?
}

enum MCPServerOutboundMessage: Encodable, Sendable {
    case response(id: MCPServerRequestID, result: CLIJSONValue)
    case error(id: MCPServerRequestID?, error: MCPServerRPCError)
    case notification(method: String, params: CLIJSONValue)
    case request(id: MCPServerRequestID, method: String, params: CLIJSONValue)

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
        case result
        case error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        switch self {
        case .response(let id, let result):
            try container.encode(id, forKey: .id)
            try container.encode(result, forKey: .result)
        case .error(let id, let error):
            if let id {
                try container.encode(id, forKey: .id)
            } else {
                try container.encodeNil(forKey: .id)
            }
            try container.encode(error, forKey: .error)
        case .notification(let method, let params):
            try container.encode(method, forKey: .method)
            try container.encode(params, forKey: .params)
        case .request(let id, let method, let params):
            try container.encode(id, forKey: .id)
            try container.encode(method, forKey: .method)
            try container.encode(params, forKey: .params)
        }
    }
}

enum MCPServerWireCodec {
    static func line(_ message: MCPServerOutboundMessage) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(message), as: UTF8.self) + "\n"
    }
}

enum MCPServerWireError: Error {
    case invalidEnvelope
}
