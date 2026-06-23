import Foundation

public enum ToolArgumentError: Error, CustomStringConvertible {
    case invalidJSON(String)
    case missingString(String)
    case missingInteger(String)

    public var description: String {
        switch self {
        case .invalidJSON(let payload):
            return "Invalid tool arguments JSON: \(payload)"
        case .missingString(let key):
            return "Missing required string argument: \(key)"
        case .missingInteger(let key):
            return "Missing required integer argument: \(key)"
        }
    }
}

public struct ToolArguments: Sendable {
    private let values: [String: Sendable]

    public init(_ json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw ToolArgumentError.invalidJSON(json)
        }
        let object: [String: JSONArgumentValue]
        do {
            object = try JSONDecoder().decode([String: JSONArgumentValue].self, from: data)
        } catch {
            throw ToolArgumentError.invalidJSON(json)
        }
        var values: [String: Sendable] = [:]
        for (key, value) in object {
            switch value {
            case .string(let string):
                values[key] = string
            case .bool(let bool):
                values[key] = bool
            case .number(let number):
                values[key] = number
            case .object(let object):
                values[key] = object
            case .array(let array):
                values[key] = array
            case .unsupported:
                continue
            }
        }
        self.values = values
    }

    private enum JSONArgumentValue: Decodable {
        case string(String)
        case bool(Bool)
        case number(String)
        case object([String: String])
        case array([String])
        case unsupported

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .unsupported
            } else if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else if let int = try? container.decode(Int.self) {
                self = .number(String(int))
            } else if let double = try? container.decode(Double.self) {
                self = .number(String(double))
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let object = try? container.decode([String: String].self) {
                self = .object(object)
            } else if let array = try? container.decode([String].self) {
                self = .array(array)
            } else {
                self = .unsupported
            }
        }
    }

    public func string(_ key: String) -> String? {
        values[key] as? String
    }

    public func requiredString(_ key: String) throws -> String {
        guard let value = string(key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolArgumentError.missingString(key)
        }
        return value
    }

    public func int(_ key: String) -> Int? {
        guard let value = string(key)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return Int(value)
    }

    public func requiredInt(_ key: String) throws -> Int {
        guard let value = int(key) else {
            throw ToolArgumentError.missingInteger(key)
        }
        return value
    }

    public func bool(_ key: String) -> Bool? {
        if let bool = values[key] as? Bool {
            return bool
        }
        switch string(key)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    public func stringDictionary(_ key: String) -> [String: String]? {
        values[key] as? [String: String]
    }

    public func stringArray(_ key: String) -> [String]? {
        if let array = values[key] as? [String] {
            let normalized = array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return normalized.isEmpty ? nil : normalized
        }
        guard let string = string(key) else { return nil }
        let normalized = string
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? nil : normalized
    }

    public static func json(_ values: [String: String]) -> String {
        jsonObject(values)
    }

    public static func json(_ values: [String: Any]) -> String {
        jsonObject(values)
    }

    private static func jsonObject(_ values: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
