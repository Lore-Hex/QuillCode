import Foundation
import QuillCodeCore
import TrustedRouter

public struct TrustedRouterModelCatalog: Sendable {
    public var models: [QuillCodeCore.ModelInfo]

    public init(models: [QuillCodeCore.ModelInfo] = Self.defaultModels) {
        self.models = models
    }

    public var defaultModelID: String {
        TrustedRouterDefaults.defaultModel
    }

    public func categories() -> [String] {
        Array(Set(models.map(\.category))).sorted()
    }

    public func models(inCategory category: String) -> [QuillCodeCore.ModelInfo] {
        models.filter { $0.category == category }.sorted { $0.displayName < $1.displayName }
    }

    public static let defaultModels: [QuillCodeCore.ModelInfo] = [
        .init(id: TrustedRouterDefaults.fastModel, provider: "trustedrouter", displayName: "Fast", category: "Recommended"),
        .init(id: TrustedRouterDefaults.fusionModel, provider: "trustedrouter", displayName: "Fusion", category: "Recommended"),
        .init(id: "z-ai/glm-5.2", provider: "z-ai", displayName: "GLM 5.2", category: "Safety"),
        .init(id: "moonshotai/kimi-k2.6", provider: "moonshotai", displayName: "Kimi K2.6", category: "Safety")
    ]
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
            return String(prefix)
        }
        return "trustedrouter"
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
        if modelID == TrustedRouterDefaults.defaultModel || provider == "trustedrouter" {
            return "Recommended"
        }
        if modelID.contains("glm") || modelID.contains("kimi") {
            return "Safety"
        }
        return provider
    }
}

public protocol TrustedRouterSessionStore: Sendable {
    func apiKey() throws -> String?
    func saveAPIKey(_ key: String) throws
}
