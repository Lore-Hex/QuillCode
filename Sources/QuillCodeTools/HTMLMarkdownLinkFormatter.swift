import Foundation

struct HTMLMarkdownLinkFormatter {
    var baseURL: URL?

    /// Resolves href/src against the page URL and sanitizes it for a markdown destination.
    func resolvedDestination(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !hasBlockedScheme(trimmed) else {
            return nil
        }
        let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteString ?? trimmed
        return sanitizedMarkdownDestination(resolved)
    }

    static func escapedLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    static func omittedInlineImageText(alt: String, byteCount: Int) -> String {
        let altText = alt.isEmpty ? "" : " \"\(alt)\""
        return "[inline image\(altText) omitted - \(byteCount / 1024) KB data URI]"
    }

    private func hasBlockedScheme(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return blockedSchemes.contains { lowered.hasPrefix($0) }
    }

    private func sanitizedMarkdownDestination(_ value: String) -> String? {
        var sanitized = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "(":
                sanitized += "%28"
            case ")":
                sanitized += "%29"
            case " ":
                sanitized += "%20"
            default:
                if scalar.value >= 0x20, scalar.value != 0x7F {
                    sanitized.unicodeScalars.append(scalar)
                }
            }
        }
        return sanitized.isEmpty ? nil : sanitized
    }

    private let blockedSchemes = [
        "javascript:", "vbscript:", "data:", "blob:", "about:"
    ]
}
