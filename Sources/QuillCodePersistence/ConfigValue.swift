import Foundation
import TOML

/// A TOML value used by config RPCs and persistence.
/// TOML has no null value; app-server nulls are represented by a nil edit and remove a path.
public enum ConfigValue: Codable, Sendable, Equatable {
    case object([String: ConfigValue])
    case array([ConfigValue])
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case offsetDateTime(Date)
    case localDateTime(LocalDateTime)
    case localDate(LocalDate)
    case localTime(LocalTime)

    public static func == (lhs: ConfigValue, rhs: ConfigValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let lhs), .object(let rhs)): lhs == rhs
        case (.array(let lhs), .array(let rhs)): lhs == rhs
        case (.string(let lhs), .string(let rhs)): lhs == rhs
        case (.integer(let lhs), .integer(let rhs)): lhs == rhs
        case (.number(let lhs), .number(let rhs)):
            lhs == rhs || (lhs.isNaN && rhs.isNaN)
        case (.bool(let lhs), .bool(let rhs)): lhs == rhs
        case (.offsetDateTime(let lhs), .offsetDateTime(let rhs)): lhs == rhs
        case (.localDateTime(let lhs), .localDateTime(let rhs)): lhs == rhs
        case (.localDate(let lhs), .localDate(let rhs)): lhs == rhs
        case (.localTime(let lhs), .localTime(let rhs)): lhs == rhs
        default: false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ConfigValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ConfigValue].self) {
            self = .object(value)
        } else if let value = try? container.decode(LocalDateTime.self) {
            self = .localDateTime(value)
        } else if let value = try? container.decode(LocalDate.self) {
            self = .localDate(value)
        } else if let value = try? container.decode(LocalTime.self) {
            self = .localTime(value)
        } else if let value = try? container.decode(Date.self) {
            self = .offsetDateTime(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported TOML value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .offsetDateTime(let value): try container.encode(value)
        case .localDateTime(let value): try container.encode(value)
        case .localDate(let value): try container.encode(value)
        case .localTime(let value): try container.encode(value)
        }
    }

    public var objectValue: [String: ConfigValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [ConfigValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var integerValue: Int64? {
        switch self {
        case .integer(let value): value
        case .number(let value) where value.isFinite && value.rounded() == value:
            Int64(exactly: value)
        default: nil
        }
    }

    public var numberValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    /// TOML supports non-finite floats, while JSON does not. Preserve their TOML value in the
    /// document and expose a deterministic string only when crossing a JSON-based config API.
    public var nonFiniteNumberStringValue: String? {
        guard case .number(let value) = self, !value.isFinite else { return nil }
        if value.isNaN { return "nan" }
        return value.sign == .minus ? "-inf" : "inf"
    }

    /// Canonical TOML representation for temporal values, suitable for JSON config RPCs.
    public var temporalStringValue: String? {
        switch self {
        case .offsetDateTime(let value):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: value)
        case .localDateTime(let value):
            let date = Self.localDateString(year: value.year, month: value.month, day: value.day)
            let time = Self.localTimeString(
                hour: value.hour,
                minute: value.minute,
                second: value.second,
                nanosecond: value.nanosecond
            )
            return "\(date)T\(time)"
        case .localDate(let value):
            return Self.localDateString(year: value.year, month: value.month, day: value.day)
        case .localTime(let value):
            return Self.localTimeString(
                hour: value.hour,
                minute: value.minute,
                second: value.second,
                nanosecond: value.nanosecond
            )
        default:
            return nil
        }
    }

    private static func localDateString(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func localTimeString(
        hour: Int,
        minute: Int,
        second: Int,
        nanosecond: Int
    ) -> String {
        let base = String(format: "%02d:%02d:%02d", hour, minute, second)
        guard nanosecond > 0 else { return base }
        let fraction = String(format: "%09d", nanosecond)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return "\(base).\(fraction)"
    }
}
