import Foundation
import QuillCodeCore
import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TrustedRouterCreditsClientError: Error, CustomStringConvertible {
    case missingAPIKey
    case invalidBalance

    public var description: String {
        switch self {
        case .missingAPIKey:
            "TrustedRouter sign-in is required to load account credits."
        case .invalidBalance:
            "TrustedRouter returned an invalid account balance."
        }
    }
}

public struct TrustedRouterCreditsClient: Sendable {
    public var apiKey: String?
    public var baseURL: String
    public var urlSession: URLSession

    public init(
        apiKey: String?,
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    public func fetch(fetchedAt: Date = Date()) async throws -> TrustedRouterCreditsSnapshot {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw TrustedRouterCreditsClientError.missingAPIKey }
        let client = try TrustedRouter(options: .init(apiKey: key, baseUrl: baseURL, urlSession: urlSession))
        let response = try await client.credits()
        guard let snapshot = TrustedRouterCreditsSnapshot(
            balance: response.balance,
            currency: response.currency,
            fetchedAt: fetchedAt
        ) else {
            throw TrustedRouterCreditsClientError.invalidBalance
        }
        return snapshot
    }

    public static func userFacingFailure(for error: Error) -> String {
        if let error = error as? TrustedRouterCreditsClientError {
            return error.description
        }
        if let error = error as? TrustedRouterError {
            switch error {
            case .authentication:
                return "TrustedRouter rejected the saved account credentials."
            case .permissionDenied:
                return "The TrustedRouter account cannot read its credit balance."
            case .notFound, .endpointNotSupported:
                return "This TrustedRouter endpoint does not provide account credits."
            case .rateLimit(_, _, _, let retryAfterSeconds):
                guard let retryAfterSeconds,
                      retryAfterSeconds.isFinite,
                      retryAfterSeconds > 0,
                      retryAfterSeconds <= 86_400 else {
                    return "TrustedRouter rate-limited the account balance refresh."
                }
                return "TrustedRouter rate-limited the account balance refresh; "
                    + "retry in \(Int(ceil(retryAfterSeconds)))s."
            case .badRequest(let statusCode, _, _), .generic(let statusCode, _, _):
                return "TrustedRouter account credits returned HTTP \(statusCode)."
            case .internalError:
                return "TrustedRouter account credits could not be refreshed."
            case .invalidResponse:
                return "TrustedRouter returned an unreadable account balance."
            }
        }
        if let error = error as? URLError {
            return "TrustedRouter account credits are temporarily unreachable (network \(error.code.rawValue))."
        }
        if error is DecodingError {
            return "TrustedRouter returned an unreadable account balance."
        }
        return "TrustedRouter account credits could not be refreshed."
    }
}
