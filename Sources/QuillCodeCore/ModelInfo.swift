import Foundation

public struct ModelCapabilities: Codable, Sendable, Hashable {
    public var contextWindowTokens: Int?
    public var inputPricePerMillionTokens: Double?
    public var outputPricePerMillionTokens: Double?
    public var inputModalities: [String]
    public var outputModalities: [String]
    public var capabilityTags: [String]
    /// nil means the catalog did not advertise support. QuillCode can still provide personality
    /// through prompt guidance, so callers treat only an explicit false as unsupported.
    public var supportsPersonality: Bool?
    public var status: String?
    public var summary: String?
    public var releaseDate: Date?
    /// TrustedRouter privacy tier for the model's routing (0 = Open, 2 = ZDR, 3 = Confidential).
    /// nil when the catalog did not advertise one. Tier 3 marks a model as eligible for
    /// confidential chats: every request runs end-to-end encrypted on TrustedRouter.
    public var privacyTier: Int?
    /// Where the model's provider routes run, normalized to lowercase region codes ("us", "eu",
    /// "cn"). Empty when the catalog made no residency claim — an empty list is UNKNOWN, never
    /// "everywhere", so region-only filters exclude it.
    public var regions: [String]

    public var isEmpty: Bool {
        contextWindowTokens == nil
            && inputPricePerMillionTokens == nil
            && outputPricePerMillionTokens == nil
            && inputModalities.isEmpty
            && outputModalities.isEmpty
            && capabilityTags.isEmpty
            && supportsPersonality == nil
            && status == nil
            && summary == nil
            && releaseDate == nil
            && privacyTier == nil
            && regions.isEmpty
    }

    public init(
        contextWindowTokens: Int? = nil,
        inputPricePerMillionTokens: Double? = nil,
        outputPricePerMillionTokens: Double? = nil,
        inputModalities: [String] = [],
        outputModalities: [String] = [],
        capabilityTags: [String] = [],
        supportsPersonality: Bool? = nil,
        status: String? = nil,
        summary: String? = nil,
        releaseDate: Date? = nil,
        privacyTier: Int? = nil,
        regions: [String] = []
    ) {
        self.contextWindowTokens = contextWindowTokens.map { max(0, $0) }
        self.inputPricePerMillionTokens = inputPricePerMillionTokens.map { max(0, $0) }
        self.outputPricePerMillionTokens = outputPricePerMillionTokens.map { max(0, $0) }
        self.inputModalities = Self.normalizedList(inputModalities)
        self.outputModalities = Self.normalizedList(outputModalities)
        self.capabilityTags = Self.normalizedList(capabilityTags)
        self.supportsPersonality = supportsPersonality
        self.status = Self.normalizedOptional(status)
        self.summary = Self.normalizedOptional(summary)
        self.releaseDate = releaseDate
        self.privacyTier = privacyTier.map { max(0, $0) }
        self.regions = Self.normalizedRegions(regions)
    }

    /// Canonical region codes: lowercase, deduplicated, common synonyms folded ("usa" → "us",
    /// "europe" → "eu", "china" → "cn") so filters and catalogs can never disagree on spelling.
    public static func normalizedRegions(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !raw.isEmpty else { continue }
            let canonical: String
            switch raw {
            case "us", "usa", "united states", "united-states", "america": canonical = "us"
            case "eu", "europe", "european union", "european-union": canonical = "eu"
            case "cn", "china", "prc": canonical = "cn"
            default: canonical = raw
            }
            guard seen.insert(canonical).inserted else { continue }
            result.append(canonical)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case contextWindowTokens
        case inputPricePerMillionTokens
        case outputPricePerMillionTokens
        case inputModalities
        case outputModalities
        case capabilityTags
        case supportsPersonality
        case status
        case summary
        case releaseDate
        case privacyTier
        case regions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            contextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens),
            inputPricePerMillionTokens: try container.decodeIfPresent(
                Double.self,
                forKey: .inputPricePerMillionTokens
            ),
            outputPricePerMillionTokens: try container.decodeIfPresent(
                Double.self,
                forKey: .outputPricePerMillionTokens
            ),
            inputModalities: try container.decodeIfPresent([String].self, forKey: .inputModalities) ?? [],
            outputModalities: try container.decodeIfPresent([String].self, forKey: .outputModalities) ?? [],
            capabilityTags: try container.decodeIfPresent([String].self, forKey: .capabilityTags) ?? [],
            supportsPersonality: try container.decodeIfPresent(Bool.self, forKey: .supportsPersonality),
            status: try container.decodeIfPresent(String.self, forKey: .status),
            summary: try container.decodeIfPresent(String.self, forKey: .summary),
            releaseDate: try container.decodeIfPresent(Date.self, forKey: .releaseDate),
            privacyTier: try container.decodeIfPresent(Int.self, forKey: .privacyTier),
            regions: try container.decodeIfPresent([String].self, forKey: .regions) ?? []
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

    public var supportsPersonality: Bool {
        capabilities.supportsPersonality != false
    }

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
