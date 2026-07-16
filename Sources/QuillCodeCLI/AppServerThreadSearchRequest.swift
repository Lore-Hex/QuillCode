import Foundation

struct AppServerThreadSearchRequest {
    let searchTerm: String
    let archived: Bool
    let sort: AppServerThreadSort
    let includesAppServerSource: Bool
    let cursor: String?
    let limit: Int?

    init(_ raw: CLIJSONValue) throws {
        guard let values = raw.objectValue else {
            throw SearchRequestDecoder.invalidType(raw, expected: "a map")
        }
        searchTerm = try SearchRequestDecoder.requiredString("searchTerm", in: values)
        archived = try SearchRequestDecoder.optionalBool("archived", in: values) ?? false
        cursor = try SearchRequestDecoder.optionalString("cursor", in: values)
        limit = try SearchRequestDecoder.optionalInteger("limit", in: values)

        let sortKey = try SearchRequestDecoder.optionalEnum(
            "sortKey",
            in: values,
            default: AppServerThreadSortKey.createdAt,
            expected: "one of `created_at`, `updated_at`, `recency_at`"
        )
        let direction = try SearchRequestDecoder.optionalEnum(
            "sortDirection",
            in: values,
            default: AppServerThreadSortDirection.desc,
            expected: "`asc` or `desc`"
        )
        sort = AppServerThreadSort(key: sortKey, direction: direction)

        let sourceKinds = try SearchRequestDecoder.optionalEnumArray(
            "sourceKinds",
            in: values,
            as: AppServerThreadSourceKind.self,
            expected: AppServerThreadSourceKind.expectedValues
        )
        includesAppServerSource = sourceKinds.isEmpty || sourceKinds.contains(.appServer)
    }
}

private enum SearchRequestDecoder {
    static func requiredString(
        _ key: String,
        in values: [String: CLIJSONValue]
    ) throws -> String {
        guard let value = values[key] else {
            throw AppServerRPCError.invalidRequest("Invalid request: missing field `\(key)`")
        }
        guard case .string(let string) = value else {
            throw invalidType(value, expected: "a string")
        }
        return string
    }

    static func optionalString(
        _ key: String,
        in values: [String: CLIJSONValue]
    ) throws -> String? {
        guard let value = values[key], value != .null else { return nil }
        guard case .string(let string) = value else {
            throw invalidType(value, expected: "a string")
        }
        return string
    }

    static func optionalBool(
        _ key: String,
        in values: [String: CLIJSONValue]
    ) throws -> Bool? {
        guard let value = values[key], value != .null else { return nil }
        guard case .bool(let bool) = value else {
            throw invalidType(value, expected: "a boolean")
        }
        return bool
    }

    static func optionalInteger(
        _ key: String,
        in values: [String: CLIJSONValue]
    ) throws -> Int? {
        guard let value = values[key], value != .null else { return nil }
        guard case .number(let number) = value,
              number.isFinite,
              number.rounded() == number,
              number >= Double(Int.min),
              number <= Double(Int.max) else {
            throw invalidType(value, expected: "u32")
        }
        return Int(number)
    }

    static func optionalEnum<Value: RawRepresentable>(
        _ key: String,
        in values: [String: CLIJSONValue],
        default defaultValue: Value,
        expected: String
    ) throws -> Value where Value.RawValue == String {
        guard let rawValue = try optionalString(key, in: values) else { return defaultValue }
        guard let value = Value(rawValue: rawValue) else {
            throw unknownVariant(rawValue, expected: expected)
        }
        return value
    }

    static func optionalEnumArray<Value: RawRepresentable>(
        _ key: String,
        in values: [String: CLIJSONValue],
        as _: Value.Type,
        expected: String
    ) throws -> [Value] where Value.RawValue == String {
        guard let value = values[key], value != .null else { return [] }
        guard case .array(let rawValues) = value else {
            throw invalidType(value, expected: "a sequence")
        }
        return try rawValues.map { rawValue in
            guard case .string(let string) = rawValue else {
                throw invalidType(rawValue, expected: "a string")
            }
            guard let value = Value(rawValue: string) else {
                throw unknownVariant(string, expected: expected)
            }
            return value
        }
    }

    static func invalidType(
        _ value: CLIJSONValue,
        expected: String
    ) -> AppServerRPCError {
        AppServerRPCError.invalidRequest(
            "Invalid request: invalid type: \(typeDescription(value)), expected \(expected)"
        )
    }

    private static func unknownVariant(
        _ value: String,
        expected: String
    ) -> AppServerRPCError {
        AppServerRPCError.invalidRequest(
            "Invalid request: unknown variant `\(value)`, expected \(expected)"
        )
    }

    private static func typeDescription(_ value: CLIJSONValue) -> String {
        switch value {
        case .string(let string):
            let encoded = try? CLIJSONCodec.encode(.string(string))
            return "string \(encoded.map { String(decoding: $0, as: UTF8.self) } ?? "\"\"")"
        case .number(let number) where number.isFinite && number.rounded() == number:
            let rendered = String(
                format: "%.0f",
                locale: Locale(identifier: "en_US_POSIX"),
                number
            )
            return "integer `\(rendered)`"
        case .number(let number):
            return "floating point `\(number)`"
        case .bool(let bool):
            return "boolean `\(bool)`"
        case .array:
            return "sequence"
        case .object:
            return "map"
        case .null:
            return "null"
        }
    }
}
