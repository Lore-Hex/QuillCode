import Foundation
import QuillCodeCore
import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TrustedRouterCreditsClientError: Error, CustomStringConvertible {
    case missingAPIKey
    case invalidKeyUsage

    public var description: String {
        switch self {
        case .missingAPIKey:
            "TrustedRouter sign-in is required to load key usage and limits."
        case .invalidKeyUsage:
            "TrustedRouter returned invalid key usage or limits."
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
        let client = try TrustedRouter(options: .init(
            apiKey: key,
            baseUrl: baseURL,
            controlBaseURL: currentKeyControlBaseURL,
            urlSession: urlSession
        ))
        let response: CurrentKeyEnvelope = try await client.request(
            method: "GET",
            path: "/key",
            plane: .control
        )
        return try response.data.snapshot(fetchedAt: fetchedAt)
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
                return "The TrustedRouter key cannot read its usage and limits."
            case .notFound, .endpointNotSupported:
                return "This TrustedRouter endpoint does not provide key usage and limits."
            case .rateLimit(_, _, _, let retryAfterSeconds):
                guard let retryAfterSeconds,
                      retryAfterSeconds.isFinite,
                      retryAfterSeconds > 0,
                      retryAfterSeconds <= 86_400 else {
                    return "TrustedRouter rate-limited the key usage refresh."
                }
                return "TrustedRouter rate-limited the key usage refresh; "
                    + "retry in \(Int(ceil(retryAfterSeconds)))s."
            case .badRequest(let statusCode, _, _), .generic(let statusCode, _, _):
                return "TrustedRouter key usage returned HTTP \(statusCode)."
            case .internalError:
                return "TrustedRouter key usage could not be refreshed."
            case .invalidResponse:
                return "TrustedRouter returned unreadable key usage."
            }
        }
        if let error = error as? URLError {
            return "TrustedRouter key usage is temporarily unreachable (network \(error.code.rawValue))."
        }
        if error is DecodingError {
            return "TrustedRouter returned unreadable key usage."
        }
        return "TrustedRouter key usage could not be refreshed."
    }

    private var currentKeyControlBaseURL: String? {
        let configured = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let standard = TrustedRouterDefaults.defaultAPIBaseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return configured == standard ? nil : configured
    }
}

private struct CurrentKeyEnvelope: Decodable {
    var data: CurrentKeyCredits
}

private struct CurrentKeyCredits: Decodable {
    var usage: Double
    var limit: Double?
    var limitRemaining: Double?
    var usageDaily: Double
    var limitDaily: Double?
    var limitDailyRemaining: Double?
    var limitDailyResetsAt: String?
    var usageWeekly: Double
    var limitWeekly: Double?
    var limitWeeklyRemaining: Double?
    var limitWeeklyResetsAt: String?
    var usageMonthly: Double
    var limitMonthly: Double?
    var limitMonthlyRemaining: Double?
    var limitMonthlyResetsAt: String?
    var budgetAlertOnly: Bool

    private enum CodingKeys: String, CodingKey {
        case usage
        case limit
        case limitRemaining = "limit_remaining"
        case usageDaily = "usage_daily"
        case limitDaily = "limit_daily"
        case limitDailyRemaining = "limit_daily_remaining"
        case limitDailyResetsAt = "limit_daily_resets_at"
        case usageWeekly = "usage_weekly"
        case limitWeekly = "limit_weekly"
        case limitWeeklyRemaining = "limit_weekly_remaining"
        case limitWeeklyResetsAt = "limit_weekly_resets_at"
        case usageMonthly = "usage_monthly"
        case limitMonthly = "limit_monthly"
        case limitMonthlyRemaining = "limit_monthly_remaining"
        case limitMonthlyResetsAt = "limit_monthly_resets_at"
        case budgetAlertOnly = "budget_alert_only"
    }

    func snapshot(fetchedAt: Date) throws -> TrustedRouterCreditsSnapshot {
        guard let lifetime = TrustedRouterCreditsWindowSnapshot(
            window: .lifetime,
            usage: usage,
            limit: limit,
            remaining: limitRemaining
        ), let daily = TrustedRouterCreditsWindowSnapshot(
            window: .daily,
            usage: usageDaily,
            limit: limitDaily,
            remaining: limitDailyRemaining,
            resetsAt: Self.date(limitDailyResetsAt)
        ), let weekly = TrustedRouterCreditsWindowSnapshot(
            window: .weekly,
            usage: usageWeekly,
            limit: limitWeekly,
            remaining: limitWeeklyRemaining,
            resetsAt: Self.date(limitWeeklyResetsAt)
        ), let monthly = TrustedRouterCreditsWindowSnapshot(
            window: .monthly,
            usage: usageMonthly,
            limit: limitMonthly,
            remaining: limitMonthlyRemaining,
            resetsAt: Self.date(limitMonthlyResetsAt)
        ), let snapshot = TrustedRouterCreditsSnapshot(
            lifetime: lifetime,
            daily: daily,
            weekly: weekly,
            monthly: monthly,
            currency: "USD",
            fetchedAt: fetchedAt,
            budgetAlertOnly: budgetAlertOnly
        ) else {
            throw TrustedRouterCreditsClientError.invalidKeyUsage
        }
        return snapshot
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
