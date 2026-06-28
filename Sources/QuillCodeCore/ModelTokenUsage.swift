import Foundation

public struct ModelTokenUsage: Codable, Sendable, Hashable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    public init(promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int? = nil) {
        self.promptTokens = max(0, promptTokens)
        self.completionTokens = max(0, completionTokens)
        self.totalTokens = max(0, totalTokens ?? (self.promptTokens + self.completionTokens))
    }

    public var contextTokens: Int {
        max(totalTokens, promptTokens + completionTokens)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ModelTokenUsageCodingKey.self)
        let promptTokens = try container.decodeFirstInt(for: [
            "promptTokens",
            "prompt_tokens",
            "inputTokens",
            "input_tokens"
        ]) ?? 0
        let completionTokens = try container.decodeFirstInt(for: [
            "completionTokens",
            "completion_tokens",
            "outputTokens",
            "output_tokens"
        ]) ?? 0
        let totalTokens = try container.decodeFirstInt(for: [
            "totalTokens",
            "total_tokens"
        ])
        self.init(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens
        )
    }
}

public enum ModelTokenUsageEvent {
    public static let summary = "Model token usage"

    public static func event(usage: ModelTokenUsage) -> ThreadEvent {
        ThreadEvent(
            kind: .notice,
            summary: summary,
            payloadJSON: try? JSONHelpers.encodePretty(usage)
        )
    }

    public static func usage(from event: ThreadEvent) -> ModelTokenUsage? {
        guard event.kind == .notice,
              event.summary == summary,
              let payloadJSON = event.payloadJSON
        else {
            return nil
        }
        return try? JSONHelpers.decode(ModelTokenUsage.self, from: payloadJSON)
    }
}

private struct ModelTokenUsageCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == ModelTokenUsageCodingKey {
    func decodeFirstInt(for keys: [String]) throws -> Int? {
        for name in keys {
            guard let key = ModelTokenUsageCodingKey(stringValue: name),
                  contains(key)
            else {
                continue
            }
            if let value = try? decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? decode(Double.self, forKey: key) {
                return Int(value)
            }
            if let value = try? decode(String.self, forKey: key),
               let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return Int(parsed)
            }
        }
        return nil
    }
}
