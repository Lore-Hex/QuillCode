import Foundation

enum AppServerRequestID: Codable, Sendable, Hashable {
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

struct AppServerRPCError: Codable, Sendable, Equatable {
    var code: Int
    var message: String
    var data: CLIJSONValue?

    init(code: Int, message: String, data: CLIJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    static let parseError = AppServerRPCError(code: -32700, message: "Parse error")
    static let invalidRequest = AppServerRPCError(code: -32600, message: "Invalid request")
    static let notInitialized = AppServerRPCError(code: -32600, message: "Not initialized")
    static let alreadyInitialized = AppServerRPCError(code: -32600, message: "Already initialized")

    static func invalidRequest(_ reason: String) -> AppServerRPCError {
        AppServerRPCError(code: -32600, message: reason)
    }

    static func methodNotFound(_ method: String) -> AppServerRPCError {
        AppServerRPCError(code: -32601, message: "Method not found: \(method)")
    }

    static func invalidParams(_ reason: String) -> AppServerRPCError {
        AppServerRPCError(code: -32602, message: "Invalid params: \(reason)")
    }

    static func internalError(_ reason: String) -> AppServerRPCError {
        AppServerRPCError(code: -32603, message: reason)
    }
}

enum AppServerInboundMessage: Sendable, Equatable {
    case request(id: AppServerRequestID, method: String, params: CLIJSONValue)
    case notification(method: String, params: CLIJSONValue)
    case response(id: AppServerRequestID, result: CLIJSONValue?, error: AppServerRPCError?)

    init(data: Data) throws {
        let envelope = try JSONDecoder().decode(AppServerInboundEnvelope.self, from: data)
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
        throw AppServerWireError.invalidEnvelope
    }
}

private struct AppServerInboundEnvelope: Decodable {
    var id: AppServerRequestID?
    var method: String?
    var params: CLIJSONValue?
    var result: CLIJSONValue?
    var error: AppServerRPCError?
}

enum AppServerOutboundMessage: Encodable, Sendable {
    case response(id: AppServerRequestID?, result: CLIJSONValue)
    case error(id: AppServerRequestID?, error: AppServerRPCError)
    case notification(method: String, params: CLIJSONValue)
    case request(id: AppServerRequestID, method: String, params: CLIJSONValue)

    private enum CodingKeys: String, CodingKey {
        case id
        case method
        case params
        case result
        case error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .response(let id, let result):
            if let id { try container.encode(id, forKey: .id) } else { try container.encodeNil(forKey: .id) }
            try container.encode(result, forKey: .result)
        case .error(let id, let error):
            if let id { try container.encode(id, forKey: .id) } else { try container.encodeNil(forKey: .id) }
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

enum AppServerWireCodec {
    static func line(_ message: AppServerOutboundMessage) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(message), as: UTF8.self) + "\n"
    }
}

struct AppServerParams: Sendable {
    let object: [String: CLIJSONValue]

    init(_ value: CLIJSONValue) throws {
        guard let object = value.objectValue else {
            throw AppServerRPCError.invalidParams("expected an object")
        }
        self.object = object
    }

    func requiredString(_ key: String, allowingEmpty: Bool = false) throws -> String {
        guard let value = object[key]?.stringValue else {
            throw AppServerRPCError.invalidParams(
                allowingEmpty ? "\(key) must be a string" : "\(key) must be a non-empty string"
            )
        }
        guard allowingEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppServerRPCError.invalidParams("\(key) must be a non-empty string")
        }
        return value
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = object[key] else { return nil }
        if value == .null { return nil }
        guard let string = value.stringValue else {
            throw AppServerRPCError.invalidParams("\(key) must be a string or null")
        }
        return string
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let value = object[key] else { return nil }
        if value == .null { return nil }
        guard let bool = value.boolValue else {
            throw AppServerRPCError.invalidParams("\(key) must be a boolean or null")
        }
        return bool
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let value = object[key] else { return nil }
        if value == .null { return nil }
        guard let number = value.numberValue,
              number.isFinite,
              number.rounded() == number,
              number >= Double(Int.min),
              number <= Double(Int.max) else {
            throw AppServerRPCError.invalidParams("\(key) must be an integer or null")
        }
        return Int(number)
    }

    func optionalArray(_ key: String) throws -> [CLIJSONValue]? {
        guard let value = object[key] else { return nil }
        if value == .null { return nil }
        guard let array = value.arrayValue else {
            throw AppServerRPCError.invalidParams("\(key) must be an array or null")
        }
        return array
    }

    func optionalObject(_ key: String) throws -> [String: CLIJSONValue]? {
        guard let value = object[key] else { return nil }
        if value == .null { return nil }
        guard let object = value.objectValue else {
            throw AppServerRPCError.invalidParams("\(key) must be an object or null")
        }
        return object
    }
}

enum AppServerWireError: Error {
    case invalidEnvelope
}

extension AppServerRPCError: Error {}
