import Foundation

enum TrustedRouterErrorBodyFormatter {
    static func streamingMessage(statusCode: Int, body: String) -> String {
        let suffix = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty
            ? "TrustedRouter streaming request failed with HTTP \(statusCode)."
            : "TrustedRouter streaming request failed with HTTP \(statusCode): \(suffix)"
    }
}
