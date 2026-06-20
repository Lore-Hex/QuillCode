import Foundation
import QuillCodeCore

public struct TrustedRouterModelCatalog: Sendable {
    public var models: [ModelInfo]

    public init(models: [ModelInfo] = Self.defaultModels) {
        self.models = models
    }

    public var defaultModelID: String {
        TrustedRouterDefaults.defaultModel
    }

    public func categories() -> [String] {
        Array(Set(models.map(\.category))).sorted()
    }

    public func models(inCategory category: String) -> [ModelInfo] {
        models.filter { $0.category == category }.sorted { $0.displayName < $1.displayName }
    }

    public static let defaultModels: [ModelInfo] = [
        .init(id: "trustedrouter/fusion", provider: "trustedrouter", displayName: "Fusion", category: "Recommended"),
        .init(id: "glm-5.2", provider: "z-ai", displayName: "GLM 5.2", category: "Safety"),
        .init(id: "kimi-k2.6", provider: "moonshot", displayName: "Kimi K2.6", category: "Safety")
    ]
}

public protocol TrustedRouterSessionStore: Sendable {
    func apiKey() throws -> String?
    func saveAPIKey(_ key: String) throws
}
