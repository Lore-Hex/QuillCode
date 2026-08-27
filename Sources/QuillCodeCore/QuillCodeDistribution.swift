import Foundation

public enum QuillCodeEdition: String, Codable, Sendable, CaseIterable, Hashable {
    case standard
    case confidential
}

public enum TrustedRouterJurisdiction: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case unitedStates = "us"
    case europeanUnion = "eu"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unitedStates: "United States"
        case .europeanUnion: "European Union"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .unitedStates: "US"
        case .europeanUnion: "EU"
        }
    }
}

/// Product policy shared by the regular and enterprise distributions.
///
/// Confidential Cowork is deliberately a policy, not a collection of UI defaults. Callers use
/// this value to sanitize persisted configuration, filter model choices, and attach a fail-closed
/// provider requirement to every model request.
public struct QuillCodeDistribution: Codable, Sendable, Hashable {
    public var edition: QuillCodeEdition

    public init(edition: QuillCodeEdition = .standard) {
        self.edition = edition
    }

    public static let standard = QuillCodeDistribution(edition: .standard)
    public static let confidential = QuillCodeDistribution(edition: .confidential)
    public static var current: QuillCodeDistribution {
        QuillCodeDistributionResolver.resolve(
            infoDictionaryEdition: Bundle.main.object(
                forInfoDictionaryKey: "QuillCodeEdition"
            ) as? String
        )
    }

    public var displayName: String {
        switch edition {
        case .standard: "Quill Cowork"
        case .confidential: "Confidential Cowork"
        }
    }

    public var brandByline: String { "by TrustedRouter" }

    public var fullBrandName: String { "\(displayName) \(brandByline)" }

    public var bundleIdentifier: String {
        switch edition {
        case .standard: "co.lorehex.QuillCowork"
        case .confidential: "com.trustedrouter.ConfidentialCowork"
        }
    }

    public var applicationHomeDirectoryName: String {
        switch edition {
        case .standard: ".quillcode"
        case .confidential: ".confidential-cowork"
        }
    }

    public var secretStorageService: String {
        switch edition {
        case .standard: "co.lorehex.QuillCowork.secrets"
        case .confidential: "com.trustedrouter.ConfidentialCowork.secrets"
        }
    }

    public var requiresConfidentialRouting: Bool { edition == .confidential }

    public var defaultModel: String {
        requiresConfidentialRouting
            ? TrustedRouterDefaults.confidentialModel
            : TrustedRouterDefaults.defaultModel
    }

    public func allowsModel(_ modelID: String, catalog: [ModelInfo]) -> Bool {
        guard requiresConfidentialRouting else { return true }
        return TrustedRouterDefaults.isConfidentialEligible(modelID, catalog: catalog)
    }

    public func enforcedModelID(_ modelID: String, catalog: [ModelInfo]) -> String {
        let canonical = TrustedRouterDefaults.canonicalModelID(modelID)
        guard allowsModel(canonical, catalog: catalog) else { return defaultModel }
        return canonical
    }

    /// Removes settings that could weaken the confidential distribution. The boundary is
    /// routing: inference always uses the official attested gateway and confidential-tier
    /// models. How the credential arrived -- OAuth sign-in or a pasted API key -- is identity,
    /// not routing, and request privacy is pinned by edition at runtime either way, so the
    /// authentication mode is deliberately left alone.
    public func enforcing(_ config: AppConfig) -> AppConfig {
        guard requiresConfidentialRouting else { return config }
        var enforced = config
        enforced.defaultModel = enforcedModelID(
            config.defaultModel,
            catalog: TrustedRouterDefaults.bundledModelCatalog
        )
        enforced.apiBaseURL = TrustedRouterDefaults.defaultAPIBaseURL
        enforced.favoriteModels = config.favoriteModels.filter {
            allowsModel($0, catalog: TrustedRouterDefaults.bundledModelCatalog)
        }
        enforced.reviewModel = TrustedRouterDefaults.confidentialModel
        return enforced
    }
}

public enum QuillCodeDistributionResolver {
    public static let environmentKey = "QUILLCODE_EDITION"

    public static func resolve(
        infoDictionaryEdition: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> QuillCodeDistribution {
        let rawValue = environment[environmentKey] ?? infoDictionaryEdition
        let edition = rawValue
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap(QuillCodeEdition.init(rawValue:))
            ?? .standard
        return QuillCodeDistribution(edition: edition)
    }
}
