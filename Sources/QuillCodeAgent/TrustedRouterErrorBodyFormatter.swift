import Foundation

enum TrustedRouterErrorBodyFormatter {
    static func streamingMessage(statusCode: Int, body: String) -> String {
        let suffix = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = suffix.isEmpty
            ? "TrustedRouter streaming request failed with HTTP \(statusCode)."
            : "TrustedRouter streaming request failed with HTTP \(statusCode): \(suffix)"
        guard let hint = hint(forStatusCode: statusCode) else {
            return base
        }
        return "\(base) \(hint)"
    }

    static func hint(forStatusCode statusCode: Int) -> String? {
        switch statusCode {
        case 401:
            return "Authentication failed — check QUILLCODE_API_KEY/TRUSTEDROUTER_API_KEY, or run `quill-code auth set-key` (or sign in again)."
        case 403:
            return "Permission denied — the API key was accepted but lacks access to this model or endpoint; check your plan/permissions or pick a different model."
        default:
            return nil
        }
    }
}
