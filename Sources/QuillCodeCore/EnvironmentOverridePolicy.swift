import Foundation

public enum EnvironmentOverrideValidation: Sendable, Equatable {
    case allowed([String: String])
    case denied(String)
}

public enum EnvironmentOverridePolicy {
    public static let maxVariables = 16
    public static let maxKeyLength = 64
    public static let maxValueLength = 512

    public static func normalizedMetadata(_ environment: [String: String]?) -> [String: String] {
        guard let environment else { return [:] }
        let pairs = environment.keys.sorted().compactMap { key -> (String, String)? in
            guard isValidKey(key),
                  let value = environment[key],
                  isValidSingleLineValue(value)
            else {
                return nil
            }
            return (key, String(value.prefix(maxValueLength)))
        }
        return Dictionary(uniqueKeysWithValues: pairs.prefix(maxVariables))
    }

    public static func validateOverrides(_ environment: [String: String]?) -> EnvironmentOverrideValidation {
        guard let environment, !environment.isEmpty else {
            return .allowed([:])
        }
        guard environment.count <= maxVariables else {
            return .denied("Shell environment supports at most \(maxVariables) variables.")
        }

        for key in environment.keys.sorted() {
            guard isValidKey(key) else {
                return .denied(
                    "Shell environment keys must be ASCII identifiers up to \(maxKeyLength) characters."
                )
            }
            guard let value = environment[key],
                  isValidSingleLineValue(value),
                  value.count <= maxValueLength
            else {
                return .denied(
                    "Shell environment values must be single-line strings up to \(maxValueLength) characters."
                )
            }
        }
        return .allowed(environment)
    }

    public static func isValidKey(_ key: String) -> Bool {
        guard !key.isEmpty,
              key.count <= maxKeyLength,
              let first = key.unicodeScalars.first,
              first == "_" || isASCIILetter(first)
        else {
            return false
        }
        return key.unicodeScalars.allSatisfy {
            $0 == "_" || isASCIILetter($0) || isASCIIDigit($0)
        }
    }

    private static func isValidSingleLineValue(_ value: String) -> Bool {
        !value.contains("\0")
            && value.rangeOfCharacter(from: .newlines) == nil
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(Int(scalar.value))
    }
}
