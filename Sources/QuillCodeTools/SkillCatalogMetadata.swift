import Foundation

public struct SkillInterfaceMetadata: Sendable, Hashable {
    public var displayName: String?
    public var shortDescription: String?
    public var iconSmall: URL?
    public var iconLarge: URL?
    public var brandColor: String?
    public var defaultPrompt: String?

    public init(
        displayName: String? = nil,
        shortDescription: String? = nil,
        iconSmall: URL? = nil,
        iconLarge: URL? = nil,
        brandColor: String? = nil,
        defaultPrompt: String? = nil
    ) {
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.iconSmall = iconSmall
        self.iconLarge = iconLarge
        self.brandColor = brandColor
        self.defaultPrompt = defaultPrompt
    }
}

public struct SkillToolDependencyMetadata: Sendable, Hashable {
    public var type: String
    public var value: String
    public var description: String?
    public var transport: String?
    public var command: String?
    public var url: String?

    public init(
        type: String,
        value: String,
        description: String? = nil,
        transport: String? = nil,
        command: String? = nil,
        url: String? = nil
    ) {
        self.type = type
        self.value = value
        self.description = description
        self.transport = transport
        self.command = command
        self.url = url
    }
}

public struct SkillCatalogMetadata: Sendable, Hashable {
    public var name: String
    public var description: String
    public var shortDescription: String?
    public var interface: SkillInterfaceMetadata?
    public var dependencies: [SkillToolDependencyMetadata]
    /// Product allow-list from `agents/openai.yaml`. An empty list means unrestricted.
    public var productRestrictions: [String]
    public var path: URL
    public var scope: SkillRootKind

    public init(
        name: String,
        description: String,
        shortDescription: String? = nil,
        interface: SkillInterfaceMetadata? = nil,
        dependencies: [SkillToolDependencyMetadata] = [],
        productRestrictions: [String] = [],
        path: URL,
        scope: SkillRootKind
    ) {
        self.name = name
        self.description = description
        self.shortDescription = shortDescription
        self.interface = interface
        self.dependencies = dependencies
        self.productRestrictions = productRestrictions
        self.path = path
        self.scope = scope
    }
}
