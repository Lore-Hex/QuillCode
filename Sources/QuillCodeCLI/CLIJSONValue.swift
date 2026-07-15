import Foundation

public enum CLIJSONValue: Codable, Sendable, Equatable {
    case object([String: CLIJSONValue])
    case array([CLIJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CLIJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: CLIJSONValue].self))
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

    var objectValue: [String: CLIJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [CLIJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

enum CLIJSONCodec {
    static func encode(_ value: CLIJSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func line(_ object: [String: CLIJSONValue]) throws -> String {
        String(decoding: try encode(.object(object)), as: UTF8.self) + "\n"
    }

    static func decode(_ data: Data) throws -> CLIJSONValue {
        try JSONDecoder().decode(CLIJSONValue.self, from: data)
    }

    static func decode(_ text: String) throws -> CLIJSONValue {
        try decode(Data(text.utf8))
    }
}
