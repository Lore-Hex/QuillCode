import Foundation

public enum ToolArgumentError: Error, CustomStringConvertible {
    case invalidJSON(String)
    case missingString(String)

    public var description: String {
        switch self {
        case .invalidJSON(let payload):
            return "Invalid tool arguments JSON: \(payload)"
        case .missingString(let key):
            return "Missing required string argument: \(key)"
        }
    }
}

public struct ToolArguments: Sendable {
    private let values: [String: Sendable]

    public init(_ json: String) throws {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ToolArgumentError.invalidJSON(json)
        }
        var values: [String: Sendable] = [:]
        for (key, value) in object {
            switch value {
            case let string as String:
                values[key] = string
            case let bool as Bool:
                values[key] = bool
            case let number as NSNumber:
                values[key] = number.stringValue
            default:
                continue
            }
        }
        self.values = values
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

    public func bool(_ key: String) -> Bool? {
        values[key] as? Bool
    }

    public static func json(_ values: [String: String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
