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
}

public struct TrustedRouterModelCatalogClient: Sendable {
    private static let publicCatalogURL = URL(string: "https://trustedrouter.com/models")!
    private static let publicCatalogExcludedModelIDs: Set<String> = [
        "trustedrouter/synth",
        "trustedrouter/synth-code",
        "trustedrouter/fusion-code"
    ]

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
        if apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return try await fetchPublicCatalog(note: nil)
        }
        do {
            return try await fetchAuthenticatedCatalog()
        } catch {
            return try await fetchPublicCatalog(
                note: "Authenticated JSON catalog failed: \(String(describing: error))"
            )
        }
    }

    private func fetchAuthenticatedCatalog() async throws -> TrustedRouterModelCatalog {
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

    private func fetchPublicCatalog(note: String?) async throws -> TrustedRouterModelCatalog {
        let (data, response) = try await urlSession.data(from: Self.publicCatalogURL)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw TrustedRouterPublicCatalogError.httpStatus(response.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw TrustedRouterPublicCatalogError.invalidUTF8
        }
        let models = Self.publicCatalogModels(fromHTML: html)
        guard !models.isEmpty else {
            throw TrustedRouterPublicCatalogError.emptyCatalog
        }
        return TrustedRouterModelCatalog(
            models: models,
            status: .publicTrustedRouter(note: note)
        )
    }

    static func publicCatalogModels(fromHTML html: String) -> [QuillCodeCore.ModelInfo] {
        let pattern = #""url":"https://trustedrouter\.com/models/([^"]+)","name":"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges == 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            let id = Self.jsonStringFragment(String(html[idRange]))
            let displayName = Self.jsonStringFragment(String(html[nameRange]))
            let canonicalID = TrustedRouterDefaults.canonicalModelID(id)
            guard canonicalID.contains("/"),
                  !Self.publicCatalogExcludedModelIDs.contains(canonicalID),
                  seen.insert(canonicalID).inserted else {
                return nil
            }
            let provider = Self.provider(from: canonicalID)
            return QuillCodeCore.ModelInfo(
                id: canonicalID,
                provider: provider,
                displayName: displayName.isEmpty ? Self.displayName(from: canonicalID) : displayName,
                category: Self.category(for: canonicalID, provider: provider)
            )
        }
    }

    private static func jsonStringFragment(_ value: String) -> String {
        let data = Data("\"\(value)\"".utf8)
        if let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
            .replacingOccurrences(of: #"\/"#, with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum TrustedRouterPublicCatalogError: Error, CustomStringConvertible {
    case httpStatus(Int)
    case invalidUTF8
    case emptyCatalog

    var description: String {
        switch self {
        case .httpStatus(let statusCode):
            return "TrustedRouter public catalog returned HTTP \(statusCode)."
        case .invalidUTF8:
            return "TrustedRouter public catalog was not UTF-8."
        case .emptyCatalog:
            return "TrustedRouter public catalog did not contain any model rows."
        }
    }
}

public protocol TrustedRouterSessionStore: Sendable {
    func apiKey() throws -> String?
    func saveAPIKey(_ key: String) throws
}
