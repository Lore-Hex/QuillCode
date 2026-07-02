import Foundation

/// How a model-call failure should be treated by the retry decorator. Only transient classes are
/// retried; everything deterministic (a 400, a bad API key, a parse error, a cancellation) is `.none`
/// and surfaces immediately.
public enum TransientFailureClass: String, Sendable, Hashable {
    /// HTTP 429 — the gateway is rate-limiting us; backing off and retrying usually clears it.
    case rateLimited
    /// HTTP 5xx (or 408) — the gateway/model is momentarily overloaded or timed out.
    case serverOverloaded
    /// A transport blip — dropped Wi-Fi, a lost connection, a request timeout, or an empty response
    /// before the stream started.
    case transport
    /// Not transient — never retry (client errors, auth, bad JSON, cancellation, anything unknown).
    case none
}

/// Classifies a thrown error into a `TransientFailureClass`. This is the taxonomy of "what model-call
/// failures are safe to retry on an unattended run" — deliberately conservative: anything not clearly
/// a transient network/gateway blip is `.none` so we never silently retry a deterministic error (a bad
/// request, an auth failure) or a user cancellation.
public enum RetryClassifier {
    public static func classify(_ error: any Error) -> TransientFailureClass {
        // A cancellation is the user stopping the run — never retry it.
        if error is CancellationError { return .none }

        if let routerError = error as? TrustedRouterAgentError {
            switch routerError {
            case .streamingHTTPError(let statusCode, _, _):
                return classify(statusCode: statusCode)
            case .emptyResponse:
                // The stream ended without producing an action before any content — a transient blip
                // worth exactly one more try (bounded by the policy).
                return .transport
            case .missingAPIKey, .invalidActionJSON, .emptyToolArguments:
                // Deterministic: retrying cannot help.
                return .none
            }
        }

        if let urlError = error as? URLError {
            return isTransient(urlError) ? .transport : .none
        }

        // Some network faults surface as a raw POSIX NSError (e.g. a socket reset by peer) rather than
        // a URLError. Retry the unambiguously transport-level ones. (errno symbols so the codes are
        // correct on both macOS and Linux CI, where the numeric values differ.)
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, Self.transientPOSIXCodes.contains(nsError.code) {
            return .transport
        }

        return .none
    }

    /// The server's rate-limit guidance riding on the error, when the HTTP layer captured response
    /// headers. Nil for transport blips and any failure that never saw a response.
    public static func rateLimitDetails(_ error: any Error) -> HTTPRateLimitDetails? {
        guard case .streamingHTTPError(_, _, let rateLimit)? = error as? TrustedRouterAgentError else {
            return nil
        }
        return rateLimit
    }

    private static let transientPOSIXCodes: Set<Int> = Set([
        ECONNRESET, ECONNABORTED, ECONNREFUSED, ETIMEDOUT,
        EHOSTUNREACH, ENETUNREACH, ENETDOWN, EPIPE,
    ].map(Int.init))

    /// The status codes worth retrying: 429 (rate limit) is its own class; 408 (request timeout),
    /// the transient 5xx (500/502/503/504), and 529 (gateway/model overloaded) are the server
    /// faltering, not our request. Deterministic codes — 4xx client errors AND deterministic 5xx like
    /// 501 (not implemented) / 505 (version unsupported) — are `.none`, since retrying cannot help.
    private static let retryableServerStatusCodes: Set<Int> = [408, 500, 502, 503, 504, 529]

    private static func classify(statusCode: Int) -> TransientFailureClass {
        if statusCode == 429 { return .rateLimited }
        if retryableServerStatusCodes.contains(statusCode) { return .serverOverloaded }
        return .none
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .dataNotAllowed,
             .internationalRoamingOff,
             // A malformed HTTP response (proxy/middleware corruption, chunked-encoding blip) is
             // typically transient — a fresh connection recovers.
             .badServerResponse:
            return true
        // NOTE: .secureConnectionFailed is deliberately EXCLUDED — a TLS/cert failure (expired,
        // self-signed, wrong host, pinning) is deterministic; retrying only wastes attempts and hides
        // the real deployment/security problem.
        default:
            return false
        }
    }
}
