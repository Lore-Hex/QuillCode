import Foundation
import QuillCodeCore

struct TrustedRouterCatalogModelsResponse: Decodable {
    var data: [TrustedRouterCatalogModel]
}

struct TrustedRouterCatalogModel: Decodable {
    var id: String
    var displayName: String?
    var capabilities: ModelCapabilities

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        id = try container.decode(String.self, forKey: "id")
        displayName = try container.firstNonEmptyString(for: ["name", "display_name", "displayName"])
        capabilities = try ModelCapabilities(
            contextWindowTokens: container.firstInt(for: Self.contextTokenKeys),
            inputPricePerMillionTokens: Self.price(
                in: container,
                directKeys: Self.inputPriceKeys,
                pricingKeys: ["input", "prompt"]
            ),
            outputPricePerMillionTokens: Self.price(
                in: container,
                directKeys: Self.outputPriceKeys,
                pricingKeys: ["output", "completion"]
            ),
            inputModalities: container.firstStringList(for: ["input_modalities", "inputModalities"]),
            outputModalities: container.firstStringList(for: ["output_modalities", "outputModalities"]),
            capabilityTags: Self.capabilityTags(in: container),
            status: container.firstNonEmptyString(for: ["status", "availability"]),
            summary: container.firstNonEmptyString(for: ["description", "summary"]),
            releaseDate: Self.releaseDate(in: container)
        )
    }

    private static let contextTokenKeys = [
        "context_window",
        "contextWindow",
        "context_length",
        "contextLength",
        "max_context_tokens",
        "maxContextTokens",
        "max_input_tokens",
        "maxInputTokens",
        "input_token_limit",
        "prompt_token_limit"
    ]

    private static let inputPriceKeys = [
        "input_price_per_million_tokens",
        "inputPricePerMillionTokens",
        "prompt_price_per_million_tokens",
        "promptPricePerMillionTokens"
    ]

    private static let outputPriceKeys = [
        "output_price_per_million_tokens",
        "outputPricePerMillionTokens",
        "completion_price_per_million_tokens",
        "completionPricePerMillionTokens"
    ]

    private static func capabilityTags(in container: KeyedDecodingContainer<FlexibleCodingKey>) throws -> [String] {
        try container.firstStringList(for: ["capabilities", "features"])
            + container.firstStringList(for: ["supported_parameters", "supportedParameters"])
    }

    private static let releaseDateKeys = [
        "created",
        "created_at",
        "createdAt",
        "release_date",
        "releaseDate"
    ]

    /// Catalogs report the model's release moment either as a unix epoch (seconds or milliseconds,
    /// OpenRouter-style `created`) or as an ISO-8601 / `yyyy-MM-dd` string. The auxiliary-model
    /// selector uses this for its recency score, so decode is best-effort: unparseable values are nil.
    private static func releaseDate(in container: KeyedDecodingContainer<FlexibleCodingKey>) -> Date? {
        if let epoch = try? container.firstDouble(for: releaseDateKeys), epoch > 0 {
            // Values beyond the year ~33658 in seconds are clearly millisecond epochs.
            return Date(timeIntervalSince1970: epoch > 1_000_000_000_000 ? epoch / 1000 : epoch)
        }
        guard let raw = try? container.firstNonEmptyString(for: releaseDateKeys) else { return nil }
        return parseDateString(raw)
    }

    private static func parseDateString(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.date(from: raw)
    }

    private static func price(
        in container: KeyedDecodingContainer<FlexibleCodingKey>,
        directKeys: [String],
        pricingKeys: [String]
    ) throws -> Double? {
        if let direct = try container.firstDouble(for: directKeys) {
            return direct
        }
        guard let pricing = try container.decodeIfPresent(FlexibleJSONObject.self, forKey: "pricing") else {
            return nil
        }
        for key in pricingKeys {
            guard let value = pricing.doubleValue(for: key) else { continue }
            return value < 1 ? value * 1_000_000 : value
        }
        return nil
    }
}

private struct FlexibleJSONObject: Decodable {
    var values: [String: FlexibleJSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        values = try Dictionary(uniqueKeysWithValues: container.allKeys.map { key in
            (key.stringValue, try container.decode(FlexibleJSONValue.self, forKey: key))
        })
    }

    func doubleValue(for key: String) -> Double? {
        values[key]?.doubleValue
    }
}

private enum FlexibleJSONValue: Decodable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case stringList([String])
    case object([String: FlexibleJSONValue])
    case ignored

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
            if let value = try? container.decode(Double.self) {
                self = .double(value)
                return
            }
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
                return
            }
            if let value = try? container.decode([String].self) {
                self = .stringList(value)
                return
            }
        }
        if let object = try? FlexibleJSONObject(from: decoder) {
            self = .object(object.values)
            return
        }
        self = .ignored
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}

struct FlexibleCodingKey: CodingKey, ExpressibleByStringLiteral {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init(stringLiteral value: String) {
        self.init(value)
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func firstNonEmptyString(for keys: [String]) throws -> String? {
        for key in keys {
            guard let raw = try? decodeIfPresent(String.self, forKey: FlexibleCodingKey(key)) else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    func firstInt(for keys: [String]) throws -> Int? {
        for key in keys {
            if let value = try? decodeIfPresent(Int.self, forKey: FlexibleCodingKey(key)) {
                return value
            }
            if let value = try? decodeIfPresent(Double.self, forKey: FlexibleCodingKey(key)) {
                return Int(value.rounded())
            }
            if let raw = try? decodeIfPresent(String.self, forKey: FlexibleCodingKey(key)),
               let value = normalizedNumber(raw).flatMap(Double.init) {
                return Int(value.rounded())
            }
        }
        return nil
    }

    func firstDouble(for keys: [String]) throws -> Double? {
        for key in keys {
            if let value = try? decodeIfPresent(Double.self, forKey: FlexibleCodingKey(key)) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: FlexibleCodingKey(key)) {
                return Double(value)
            }
            if let raw = try? decodeIfPresent(String.self, forKey: FlexibleCodingKey(key)),
               let value = normalizedNumber(raw).flatMap(Double.init) {
                return value
            }
        }
        return nil
    }

    func firstStringList(for keys: [String]) throws -> [String] {
        for key in keys {
            if let values = try? decodeIfPresent([String].self, forKey: FlexibleCodingKey(key)) {
                return values
            }
            if let value = try? decodeIfPresent(String.self, forKey: FlexibleCodingKey(key)) {
                return value
                    .split { character in character == "," || character == "|" || character == "/" }
                    .map(String.init)
            }
            if let valueMap = try? decodeIfPresent([String: Bool].self, forKey: FlexibleCodingKey(key)) {
                return valueMap
                    .filter { $0.value }
                    .map(\.key)
                    .sorted()
            }
        }
        return []
    }

    private func normalizedNumber(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return normalized.isEmpty ? nil : normalized
    }
}
