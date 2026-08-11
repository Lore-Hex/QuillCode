import Foundation

/// Some data APIs report a failed request in a JSON body while returning HTTP 200. Treat only
/// explicit, top-level failure signals as errors so ordinary JSON documents remain fetchable.
public enum WebFetchSemanticFailure {
    public static func description(in text: String) -> String? {
        guard let object = topLevelObject(in: text) else { return nil }
        let fields = Dictionary(uniqueKeysWithValues: object.map { key, value in
            (key.lowercased(), value)
        })

        if let status = fields["status"] as? String {
            let normalized = status
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            if failureStatuses.contains(normalized) {
                return detail(status: status, fields: fields)
            }
        }

        if fields["success"] as? Bool == false,
           !containsUsablePayload(fields) {
            return detail(status: "success=false", fields: fields)
        }
        return nil
    }

    private static func topLevelObject(in text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [trimmed, jsonObjectSuffix(in: trimmed)].compactMap { $0 }
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            return object
        }
        return nil
    }

    private static func jsonObjectSuffix(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        return String(text[start...])
    }

    private static func containsUsablePayload(_ fields: [String: Any]) -> Bool {
        ["data", "result", "results", "series", "items"].contains { key in
            guard let value = fields[key] else { return false }
            if value is NSNull { return false }
            if let values = value as? [Any] { return !values.isEmpty }
            if let values = value as? [String: Any] { return !values.isEmpty }
            if let value = value as? String {
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
    }

    private static func detail(status: String, fields: [String: Any]) -> String {
        let message = ["message", "error", "detail", "reason"]
            .compactMap { fields[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        if let message {
            return "API status \(status): \(message)"
        }
        return "API status \(status)"
    }

    private static let failureStatuses: Set<String> = [
        "REQUEST_NOT_PROCESSED",
        "ERROR",
        "FAILED",
        "FAILURE",
        "DENIED",
        "UNAUTHORIZED",
        "FORBIDDEN",
        "INVALID_REQUEST",
        "NOT_FOUND",
        "RATE_LIMITED",
        "TOO_MANY_REQUESTS",
    ]
}
