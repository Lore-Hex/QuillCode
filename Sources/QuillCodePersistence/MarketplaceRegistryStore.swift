import Foundation

public enum MarketplaceSourceType: String, Sendable, Equatable {
    case local
    case git
}

public struct MarketplaceRegistration: Sendable, Equatable {
    public var name: String
    public var sourceType: MarketplaceSourceType
    public var source: String
    public var refName: String?
    public var sparsePaths: [String]
    public var lastUpdated: String
    public var lastRevision: String?

    public init(
        name: String,
        sourceType: MarketplaceSourceType,
        source: String,
        refName: String? = nil,
        sparsePaths: [String] = [],
        lastUpdated: String,
        lastRevision: String? = nil
    ) {
        self.name = name
        self.sourceType = sourceType
        self.source = source
        self.refName = refName
        self.sparsePaths = sparsePaths
        self.lastUpdated = lastUpdated
        self.lastRevision = lastRevision
    }
}

public enum MarketplaceRegistryError: Error, CustomStringConvertible, Sendable, Equatable {
    case invalidName(String)
    case invalidRegistration(String)

    public var description: String {
        switch self {
        case .invalidName(let name):
            "Invalid marketplace name `\(name)`."
        case .invalidRegistration(let name):
            "Marketplace `\(name)` has an invalid configuration."
        }
    }
}

/// Preserves marketplace registrations inside the shared user `config.toml` document.
///
/// The store owns only the `[marketplaces]` table. Every write loads and rewrites the complete
/// TOML document atomically so unrelated QuillCode and Codex-compatible settings survive.
public struct MarketplaceRegistryStore: Sendable {
    public static let maximumMarketplaces = 64
    public static let maximumSourceBytes = 4_096
    public static let maximumSparsePaths = 64
    public static let maximumSparsePathBytes = 1_024

    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func registrations() throws -> [MarketplaceRegistration] {
        let document = try ConfigDocumentStore(fileURL: fileURL).load()
        let marketplaces = try Self.marketplaceValues(in: document)
        return try marketplaces.keys.sorted().map { name in
            guard let value = marketplaces[name] else {
                throw MarketplaceRegistryError.invalidRegistration(name)
            }
            return try Self.registration(name: name, value: value)
        }
    }

    public func registration(named name: String) throws -> MarketplaceRegistration? {
        let normalized = try Self.normalizedName(name)
        return try registrations().first { $0.name == normalized }
    }

    public func upsert(_ registration: MarketplaceRegistration) throws {
        let registration = try Self.validated(registration)
        let store = ConfigDocumentStore(fileURL: fileURL)
        var document = try store.load()
        var marketplaces = try Self.marketplaceValues(in: document)
        guard marketplaces.count < Self.maximumMarketplaces || marketplaces[registration.name] != nil else {
            throw MarketplaceRegistryError.invalidRegistration("marketplaces")
        }
        marketplaces[registration.name] = Self.configValue(registration)
        document.values["marketplaces"] = .object(marketplaces)
        try store.save(document)
    }

    @discardableResult
    public func remove(named name: String) throws -> Bool {
        let normalized = try Self.normalizedName(name)
        let store = ConfigDocumentStore(fileURL: fileURL)
        var document = try store.load()
        var marketplaces = try Self.marketplaceValues(in: document)
        guard marketplaces.removeValue(forKey: normalized) != nil else { return false }
        document.values["marketplaces"] = marketplaces.isEmpty ? nil : .object(marketplaces)
        try store.save(document)
        return true
    }

    private static func marketplaceValues(
        in document: ConfigDocument
    ) throws -> [String: ConfigValue] {
        guard let rawMarketplaces = document.values["marketplaces"] else { return [:] }
        guard let marketplaces = rawMarketplaces.objectValue,
              marketplaces.count <= maximumMarketplaces
        else {
            throw MarketplaceRegistryError.invalidRegistration("marketplaces")
        }
        for (name, value) in marketplaces {
            _ = try registration(name: name, value: value)
        }
        return marketplaces
    }

    private static func registration(name: String, value: ConfigValue) throws -> MarketplaceRegistration {
        let name = try normalizedName(name)
        guard let object = value.objectValue,
              let rawSourceType = object["source_type"]?.stringValue,
              let sourceType = MarketplaceSourceType(rawValue: rawSourceType),
              let source = bounded(object["source"]?.stringValue, maximumBytes: maximumSourceBytes),
              let lastUpdated = bounded(object["last_updated"]?.stringValue, maximumBytes: 80)
        else {
            throw MarketplaceRegistryError.invalidRegistration(name)
        }
        let sparseValues = object["sparse_paths"]?.arrayValue ?? []
        guard sparseValues.count <= maximumSparsePaths else {
            throw MarketplaceRegistryError.invalidRegistration(name)
        }
        let sparsePaths = try sparseValues.map { value -> String in
            guard let path = bounded(value.stringValue, maximumBytes: maximumSparsePathBytes) else {
                throw MarketplaceRegistryError.invalidRegistration(name)
            }
            return path
        }
        let refName = try boundedOptional(
            object["ref_name"]?.stringValue,
            maximumBytes: 1_024,
            registration: name
        )
        let lastRevision = try boundedOptional(
            object["last_revision"]?.stringValue,
            maximumBytes: 160,
            registration: name
        )
        let registration = MarketplaceRegistration(
            name: name,
            sourceType: sourceType,
            source: source,
            refName: refName,
            sparsePaths: sparsePaths,
            lastUpdated: lastUpdated,
            lastRevision: lastRevision
        )
        return try validated(registration)
    }

    private static func validated(_ registration: MarketplaceRegistration) throws -> MarketplaceRegistration {
        let name = try normalizedName(registration.name)
        guard let source = bounded(registration.source, maximumBytes: maximumSourceBytes),
              let lastUpdated = bounded(registration.lastUpdated, maximumBytes: 80),
              registration.sparsePaths.count <= maximumSparsePaths,
              registration.sparsePaths.allSatisfy({
                  bounded($0, maximumBytes: maximumSparsePathBytes) != nil
              })
        else {
            throw MarketplaceRegistryError.invalidRegistration(name)
        }
        let refName = try boundedOptional(
            registration.refName,
            maximumBytes: 1_024,
            registration: name
        )
        let lastRevision = try boundedOptional(
            registration.lastRevision,
            maximumBytes: 160,
            registration: name
        )
        return MarketplaceRegistration(
            name: name,
            sourceType: registration.sourceType,
            source: source,
            refName: refName,
            sparsePaths: registration.sparsePaths,
            lastUpdated: lastUpdated,
            lastRevision: lastRevision
        )
    }

    private static func configValue(_ registration: MarketplaceRegistration) -> ConfigValue {
        var values: [String: ConfigValue] = [
            "source_type": .string(registration.sourceType.rawValue),
            "source": .string(registration.source),
            "sparse_paths": .array(registration.sparsePaths.map(ConfigValue.string)),
            "last_updated": .string(registration.lastUpdated)
        ]
        if let refName = registration.refName { values["ref_name"] = .string(refName) }
        if let lastRevision = registration.lastRevision {
            values["last_revision"] = .string(lastRevision)
        }
        return .object(values)
    }

    private static func normalizedName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty,
              normalized.utf8.count <= 128,
              normalized.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
              })
        else {
            throw MarketplaceRegistryError.invalidName(name)
        }
        return normalized
    }

    private static func bounded(_ value: String?, maximumBytes: Int) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.contains("\0"),
              normalized.utf8.count <= maximumBytes
        else { return nil }
        return normalized
    }

    private static func boundedOptional(
        _ value: String?,
        maximumBytes: Int,
        registration: String
    ) throws -> String? {
        guard let value else { return nil }
        guard let bounded = bounded(value, maximumBytes: maximumBytes) else {
            throw MarketplaceRegistryError.invalidRegistration(registration)
        }
        return bounded
    }
}
