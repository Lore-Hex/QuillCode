import Foundation

public struct ModelCapabilities: Codable, Sendable, Hashable {
    public var contextWindowTokens: Int?
    public var inputPricePerMillionTokens: Double?
    public var outputPricePerMillionTokens: Double?
    public var inputModalities: [String]
    public var outputModalities: [String]
    public var capabilityTags: [String]
    public var status: String?
    public var summary: String?
    public var releaseDate: Date?

    public var isEmpty: Bool {
        contextWindowTokens == nil
            && inputPricePerMillionTokens == nil
            && outputPricePerMillionTokens == nil
            && inputModalities.isEmpty
            && outputModalities.isEmpty
            && capabilityTags.isEmpty
            && status == nil
            && summary == nil
            && releaseDate == nil
    }

    public init(
        contextWindowTokens: Int? = nil,
        inputPricePerMillionTokens: Double? = nil,
        outputPricePerMillionTokens: Double? = nil,
        inputModalities: [String] = [],
        outputModalities: [String] = [],
        capabilityTags: [String] = [],
        status: String? = nil,
        summary: String? = nil,
        releaseDate: Date? = nil
    ) {
        self.contextWindowTokens = contextWindowTokens.map { max(0, $0) }
        self.inputPricePerMillionTokens = inputPricePerMillionTokens.map { max(0, $0) }
        self.outputPricePerMillionTokens = outputPricePerMillionTokens.map { max(0, $0) }
        self.inputModalities = Self.normalizedList(inputModalities)
        self.outputModalities = Self.normalizedList(outputModalities)
        self.capabilityTags = Self.normalizedList(capabilityTags)
        self.status = Self.normalizedOptional(status)
        self.summary = Self.normalizedOptional(summary)
        self.releaseDate = releaseDate
    }

    private enum CodingKeys: String, CodingKey {
        case contextWindowTokens
        case inputPricePerMillionTokens
        case outputPricePerMillionTokens
        case inputModalities
        case outputModalities
        case capabilityTags
        case status
        case summary
        case releaseDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            contextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens),
            inputPricePerMillionTokens: try container.decodeIfPresent(Double.self, forKey: .inputPricePerMillionTokens),
            outputPricePerMillionTokens: try container.decodeIfPresent(Double.self, forKey: .outputPricePerMillionTokens),
            inputModalities: try container.decodeIfPresent([String].self, forKey: .inputModalities) ?? [],
            outputModalities: try container.decodeIfPresent([String].self, forKey: .outputModalities) ?? [],
            capabilityTags: try container.decodeIfPresent([String].self, forKey: .capabilityTags) ?? [],
            status: try container.decodeIfPresent(String.self, forKey: .status),
            summary: try container.decodeIfPresent(String.self, forKey: .summary),
            releaseDate: try container.decodeIfPresent(Date.self, forKey: .releaseDate)
        )
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ModelInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: String
    public var displayName: String
    public var category: String
    public var capabilities: ModelCapabilities

    public init(
        id: String,
        provider: String,
        displayName: String,
        category: String,
        capabilities: ModelCapabilities = .init()
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.category = category
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case displayName
        case category
        case capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            provider: try container.decode(String.self, forKey: .provider),
            displayName: try container.decode(String.self, forKey: .displayName),
            category: try container.decode(String.self, forKey: .category),
            capabilities: try container.decodeIfPresent(ModelCapabilities.self, forKey: .capabilities) ?? .init()
        )
    }
}

public struct ModelSortKey: Sendable, Hashable, Comparable {
    public var recommendedRank: Int
    public var provider: String
    public var displayName: String
    public var id: String

    public init(recommendedRank: Int, provider: String, displayName: String, id: String) {
        self.recommendedRank = recommendedRank
        self.provider = provider
        self.displayName = displayName
        self.id = id
    }

    public static func < (lhs: ModelSortKey, rhs: ModelSortKey) -> Bool {
        if lhs.recommendedRank != rhs.recommendedRank {
            return lhs.recommendedRank < rhs.recommendedRank
        }
        if lhs.provider != rhs.provider { return lhs.provider < rhs.provider }
        if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
        return lhs.id < rhs.id
    }
}
