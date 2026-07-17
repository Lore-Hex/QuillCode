public enum QuillCodeFeatureStage: String, Codable, Sendable, CaseIterable {
    case beta
    case underDevelopment
    case stable
    case deprecated
    case removed
}

public enum QuillCodeFeature: String, Codable, Sendable, CaseIterable {
    case hooks
    case memories
}

public struct QuillCodeFeatureDefinition: Codable, Sendable, Equatable {
    public var feature: QuillCodeFeature
    public var stage: QuillCodeFeatureStage
    public var displayName: String?
    public var description: String?
    public var announcement: String?
    public var defaultEnabled: Bool
    public var supportsRuntimeEnablement: Bool

    public init(
        feature: QuillCodeFeature,
        stage: QuillCodeFeatureStage,
        displayName: String? = nil,
        description: String? = nil,
        announcement: String? = nil,
        defaultEnabled: Bool,
        supportsRuntimeEnablement: Bool = false
    ) {
        self.feature = feature
        self.stage = stage
        self.displayName = displayName
        self.description = description
        self.announcement = announcement
        self.defaultEnabled = defaultEnabled
        self.supportsRuntimeEnablement = supportsRuntimeEnablement
    }
}

public enum QuillCodeFeatureCatalog {
    public static let all: [QuillCodeFeatureDefinition] = [
        QuillCodeFeatureDefinition(
            feature: .hooks,
            stage: .stable,
            defaultEnabled: true
        ),
        QuillCodeFeatureDefinition(
            feature: .memories,
            stage: .beta,
            displayName: "Memories",
            description: "Let QuillCode reuse durable preferences and project context across tasks.",
            announcement: "QuillCode can remember useful context between tasks.",
            defaultEnabled: true,
            supportsRuntimeEnablement: true
        )
    ]

    public static func definition(named name: String) -> QuillCodeFeatureDefinition? {
        guard let feature = QuillCodeFeature(rawValue: name) else { return nil }
        return definitionsByFeature[feature]
    }

    public static func definition(for feature: QuillCodeFeature) -> QuillCodeFeatureDefinition {
        guard let definition = definitionsByFeature[feature] else {
            preconditionFailure("Every QuillCode feature must have one catalog definition")
        }
        return definition
    }

    private static let definitionsByFeature = Dictionary(
        uniqueKeysWithValues: all.map { ($0.feature, $0) }
    )
}
