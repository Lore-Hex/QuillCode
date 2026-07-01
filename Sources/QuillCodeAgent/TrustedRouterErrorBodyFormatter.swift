import Foundation

enum TrustedRouterErrorBodyFormatter {
    static func streamingMessage(statusCode: Int, body: String) -> String {
        let suffix = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = suffix.isEmpty
            ? "TrustedRouter streaming request failed with HTTP \(statusCode)."
            : "TrustedRouter streaming request failed with HTTP \(statusCode): \(suffix)"
        guard let hint = hint(forStatusCode: statusCode) else { return base }
        return "\(base) \(hint)"
    }

    /// A next-step hint for the statuses where the raw code routinely sends people (and the model)
    /// down the wrong road: 401/403 look identical ("it failed") but need opposite responses.
    static func hint(forStatusCode statusCode: Int) -> String? {
        switch statusCode {
        case 401:
            return "Authentication failed — the API key is missing, invalid, or expired. Sign in again (or refresh the developer override key) in Settings."
        case 403:
            return "Permission denied — the key is valid but not allowed to use this model or route. Pick a different model or check the account's plan."
        default:
            return nil
        }
    }
}
