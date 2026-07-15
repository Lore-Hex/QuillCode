import Foundation

public struct CodexPluginMarketplaceCatalogDiscovery: Sendable, Hashable {
    public var marketplaces: [CodexPluginMarketplaceCatalog]
    public var errors: [CodexPluginMarketplaceCatalogError]

    public init(
        marketplaces: [CodexPluginMarketplaceCatalog],
        errors: [CodexPluginMarketplaceCatalogError]
    ) {
        self.marketplaces = marketplaces
        self.errors = errors
    }
}

public struct CodexPluginMarketplaceCatalogError: Sendable, Hashable {
    public var marketplacePath: URL
    public var message: String

    public init(marketplacePath: URL, message: String) {
        self.marketplacePath = marketplacePath
        self.message = message
    }
}

public struct CodexPluginMarketplaceCatalog: Sendable, Hashable {
    public var name: String
    public var path: URL
    public var displayName: String?
    public var plugins: [CodexPluginMarketplaceEntry]

    public init(
        name: String,
        path: URL,
        displayName: String?,
        plugins: [CodexPluginMarketplaceEntry]
    ) {
        self.name = name
        self.path = path
        self.displayName = displayName
        self.plugins = plugins
    }
}

public struct CodexPluginMarketplaceEntry: Sendable, Hashable {
    public var name: String
    public var source: CodexPluginCatalogSource
    public var installPolicy: CodexPluginInstallPolicy
    public var authPolicy: CodexPluginAuthPolicy
    public var category: String?
    public var package: CodexPluginPackageMetadata?

    public init(
        name: String,
        source: CodexPluginCatalogSource,
        installPolicy: CodexPluginInstallPolicy,
        authPolicy: CodexPluginAuthPolicy,
        category: String?,
        package: CodexPluginPackageMetadata?
    ) {
        self.name = name
        self.source = source
        self.installPolicy = installPolicy
        self.authPolicy = authPolicy
        self.category = category
        self.package = package
    }
}

public enum CodexPluginCatalogSource: Sendable, Hashable {
    case local(path: URL, relativePath: String)

    public var localPath: URL {
        switch self {
        case .local(let path, _): path
        }
    }

    public var localRelativePath: String {
        switch self {
        case .local(_, let relativePath): relativePath
        }
    }
}

public enum CodexPluginInstallPolicy: String, Sendable, Hashable {
    case notAvailable = "NOT_AVAILABLE"
    case available = "AVAILABLE"
    case installedByDefault = "INSTALLED_BY_DEFAULT"
}

public enum CodexPluginAuthPolicy: String, Sendable, Hashable {
    case onInstall = "ON_INSTALL"
    case onUse = "ON_USE"
}

public struct CodexPluginPackageMetadata: Sendable, Hashable {
    public var name: String
    public var version: String?
    public var description: String?
    public var keywords: [String]
    public var interface: CodexPluginInterfaceMetadata?

    public init(
        name: String,
        version: String?,
        description: String?,
        keywords: [String],
        interface: CodexPluginInterfaceMetadata?
    ) {
        self.name = name
        self.version = version
        self.description = description
        self.keywords = keywords
        self.interface = interface
    }
}

public struct CodexPluginInterfaceMetadata: Sendable, Hashable {
    public var displayName: String?
    public var shortDescription: String?
    public var longDescription: String?
    public var developerName: String?
    public var category: String?
    public var capabilities: [String]
    public var websiteURL: String?
    public var privacyPolicyURL: String?
    public var termsOfServiceURL: String?
    public var defaultPrompts: [String]?
    public var brandColor: String?
    public var composerIcon: URL?
    public var composerIconURL: String?
    public var logo: URL?
    public var logoDark: URL?
    public var logoURL: String?
    public var logoURLDark: String?
    public var screenshots: [URL]
    public var screenshotURLs: [String]

    public init(
        displayName: String? = nil,
        shortDescription: String? = nil,
        longDescription: String? = nil,
        developerName: String? = nil,
        category: String? = nil,
        capabilities: [String] = [],
        websiteURL: String? = nil,
        privacyPolicyURL: String? = nil,
        termsOfServiceURL: String? = nil,
        defaultPrompts: [String]? = nil,
        brandColor: String? = nil,
        composerIcon: URL? = nil,
        composerIconURL: String? = nil,
        logo: URL? = nil,
        logoDark: URL? = nil,
        logoURL: String? = nil,
        logoURLDark: String? = nil,
        screenshots: [URL] = [],
        screenshotURLs: [String] = []
    ) {
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.developerName = developerName
        self.category = category
        self.capabilities = capabilities
        self.websiteURL = websiteURL
        self.privacyPolicyURL = privacyPolicyURL
        self.termsOfServiceURL = termsOfServiceURL
        self.defaultPrompts = defaultPrompts
        self.brandColor = brandColor
        self.composerIcon = composerIcon
        self.composerIconURL = composerIconURL
        self.logo = logo
        self.logoDark = logoDark
        self.logoURL = logoURL
        self.logoURLDark = logoURLDark
        self.screenshots = screenshots
        self.screenshotURLs = screenshotURLs
    }
}
