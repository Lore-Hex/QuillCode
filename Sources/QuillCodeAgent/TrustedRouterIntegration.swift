import Foundation
import QuillCodeCore
import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TrustedRouterModelCatalog: Sendable {
    public var models: [QuillCodeCore.ModelInfo]
    public var status: QuillCodeCore.ModelCatalogStatus

    public init(
        models: [QuillCodeCore.ModelInfo] = Self.defaultModels,
        status: QuillCodeCore.ModelCatalogStatus = .bundled
    ) {
        self.models = Self.normalized(models)
        self.status = status
    }

    public var defaultModelID: String {
        TrustedRouterDefaults.defaultModel
    }

    public func categories() -> [String] {
        Array(Set(models.map(\.category))).sorted(by: TrustedRouterDefaults.compareModelCategories)
    }

    public func models(inCategory category: String) -> [QuillCodeCore.ModelInfo] {
        models.filter { $0.category == category }.sorted(by: TrustedRouterDefaults.compareModels)
    }

    public static let defaultModels: [QuillCodeCore.ModelInfo] = TrustedRouterDefaults.normalizedModelCatalog([])

    public static func normalized(_ models: [QuillCodeCore.ModelInfo]) -> [QuillCodeCore.ModelInfo] {
        TrustedRouterDefaults.normalizedModelCatalog(models)
    }

    public static func sortModels(_ lhs: QuillCodeCore.ModelInfo, _ rhs: QuillCodeCore.ModelInfo) -> Bool {
        TrustedRouterDefaults.compareModels(lhs, rhs)
    }

    public static func categoryRank(_ category: String) -> Int {
        TrustedRouterDefaults.modelCategoryRank(category)
    }
}

public struct TrustedRouterModelCatalogClient: Sendable {
    public var apiKey: String?
    public var baseURL: String
    public var urlSession: URLSession

    public init(
        apiKey: String? = nil,
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    public func fetch() async throws -> TrustedRouterModelCatalog {
        let client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL, urlSession: urlSession))
        let data: Data = try await client.request(method: "GET", path: "/models")
        let response = try JSONDecoder().decode(TrustedRouterCatalogModelsResponse.self, from: data)
        let models = response.data.map { model in
            let provider = Self.provider(from: model.id)
            return QuillCodeCore.ModelInfo(
                id: TrustedRouterDefaults.canonicalModelID(model.id),
                provider: provider,
                displayName: model.displayName ?? Self.displayName(from: model.id),
                category: Self.category(for: model.id, provider: provider),
                capabilities: model.capabilities
            )
        }
        guard !models.isEmpty else {
            return TrustedRouterModelCatalog(
                models: TrustedRouterModelCatalog.defaultModels,
                status: .fallbackAfterFailure("TrustedRouter returned an empty model catalog.")
            )
        }
        return TrustedRouterModelCatalog(models: models, status: .liveTrustedRouter())
    }

    public static func provider(from modelID: String) -> String {
        TrustedRouterDefaults.provider(fromModelID: modelID)
    }

    public static func displayName(from modelID: String) -> String {
        TrustedRouterDefaults.displayName(fromModelID: modelID)
    }

    public static func category(for modelID: String, provider: String) -> String {
        TrustedRouterDefaults.category(forModelID: modelID, provider: provider)
    }
}

public protocol TrustedRouterSessionStore: Sendable {
    func apiKey() throws -> String?
    func saveAPIKey(_ key: String) throws
}
