import Foundation
import QuillCodeCore
import TrustedRouter

public struct TrustedRouterModelCatalog: Sendable {
    public var models: [QuillCodeCore.ModelInfo]

    public init(models: [QuillCodeCore.ModelInfo] = Self.defaultModels) {
        self.models = Self.normalized(models)
    }

    public var defaultModelID: String {
        TrustedRouterDefaults.defaultModel
    }

    public func categories() -> [String] {
        Array(Set(models.map(\.category))).sorted()
    }

    public func models(inCategory category: String) -> [QuillCodeCore.ModelInfo] {
        models.filter { $0.category == category }.sorted(by: Self.sortModels)
    }

    public static let defaultModels: [QuillCodeCore.ModelInfo] = TrustedRouterDefaults.bundledModelCatalog

    public static func normalized(_ models: [QuillCodeCore.ModelInfo]) -> [QuillCodeCore.ModelInfo] {
        TrustedRouterDefaults.catalogIncludingBundledDefaults(models).sorted(by: sortModels)
    }

    public static func sortModels(_ lhs: QuillCodeCore.ModelInfo, _ rhs: QuillCodeCore.ModelInfo) -> Bool {
        let lhsCategoryRank = categoryRank(lhs.category)
        let rhsCategoryRank = categoryRank(rhs.category)
        if lhsCategoryRank != rhsCategoryRank { return lhsCategoryRank < rhsCategoryRank }
        return TrustedRouterDefaults.modelSortKey(
            id: lhs.id,
            provider: lhs.provider,
            displayName: lhs.displayName
        ) < TrustedRouterDefaults.modelSortKey(
            id: rhs.id,
            provider: rhs.provider,
            displayName: rhs.displayName
        )
    }

    public static func categoryRank(_ category: String) -> Int {
        TrustedRouterDefaults.modelCategoryRank(category)
    }
}

public struct TrustedRouterModelCatalogClient: Sendable {
    public var apiKey: String?
    public var baseURL: String

    public init(apiKey: String? = nil, baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func fetch() async throws -> TrustedRouterModelCatalog {
        let client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL))
        let response = try await client.models()
        let models = response.data.map { model in
            let provider = Self.provider(from: model.id)
            return QuillCodeCore.ModelInfo(
                id: model.id,
                provider: provider,
                displayName: Self.displayName(from: model.id),
                category: Self.category(for: model.id, provider: provider)
            )
        }
        return TrustedRouterModelCatalog(models: models.isEmpty ? TrustedRouterModelCatalog.defaultModels : models)
    }

    public static func provider(from modelID: String) -> String {
        if let prefix = modelID.split(separator: "/").first {
            return TrustedRouterDefaults.canonicalProvider(String(prefix))
        }
        return TrustedRouterDefaults.trustedRouterProvider
    }

    public static func displayName(from modelID: String) -> String {
        let raw = modelID.split(separator: "/").last.map(String.init) ?? modelID
        return raw
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    public static func category(for modelID: String, provider: String) -> String {
        if TrustedRouterDefaults.isRecommendedModel(modelID, provider: provider) {
            return TrustedRouterDefaults.recommendedCategory
        }
        if TrustedRouterDefaults.isSafetyReviewerModel(modelID) {
            return TrustedRouterDefaults.safetyCategory
        }
        return provider
    }
}

public protocol TrustedRouterSessionStore: Sendable {
    func apiKey() throws -> String?
    func saveAPIKey(_ key: String) throws
}
