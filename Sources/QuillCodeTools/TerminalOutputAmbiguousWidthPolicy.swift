import Foundation

public enum TerminalOutputAmbiguousWidthPolicy: Sendable {
    case narrow
    case wide

    public static let environmentOverrideName = "QUILLCODE_TERMINAL_AMBIGUOUS_WIDTH"

    var cellWidth: Int {
        switch self {
        case .narrow:
            return 1
        case .wide:
            return 2
        }
    }

    public static func automatic(
        localeIdentifier: String? = Locale.current.identifier,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TerminalOutputAmbiguousWidthPolicy {
        if let override = environment[environmentOverrideName],
           let policy = policyOverrideValue(override) {
            return policy
        }
        return isCJKLocaleIdentifier(localeIdentifierCandidate(localeIdentifier, environment: environment)) ? .wide : .narrow
    }

    private static func policyOverrideValue(_ rawValue: String) -> TerminalOutputAmbiguousWidthPolicy? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "narrow", "single", "1":
            return .narrow
        case "wide", "cjk", "2":
            return .wide
        default:
            return nil
        }
    }

    private static func isCJKLocaleIdentifier(_ localeIdentifier: String?) -> Bool {
        guard let languageCode = normalizedLocaleComponents(localeIdentifier).first else {
            return false
        }
        return cjkLanguageCodes.contains(languageCode)
    }

    private static func localeIdentifierCandidate(
        _ localeIdentifier: String?,
        environment: [String: String]
    ) -> String? {
        [
            environment["LC_ALL"],
            environment["LC_CTYPE"],
            environment["LANG"],
            localeIdentifier
        ].first(where: isPresentLocaleIdentifier) ?? nil
    }

    private static func isPresentLocaleIdentifier(_ candidate: String?) -> Bool {
        candidate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private static func normalizedLocaleComponents(_ localeIdentifier: String?) -> [String] {
        guard let localeIdentifier else { return [] }
        return localeIdentifier
            .lowercased()
            .split { character in
                character == "_" || character == "-" || character == "." || character == "@"
            }
            .map(String.init)
    }

    private static let cjkLanguageCodes: Set<String> = [
        "ja",
        "ko",
        "zh",
        "cmn",
        "yue",
        "wuu",
        "hak",
        "nan",
        "lzh"
    ]
}
