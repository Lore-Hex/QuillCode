import Foundation

extension TestCommandLexicon {
    /// Identity for same-scope re-run matching.
    ///
    /// The inverted default is deliberate: an enumerated selector whitelist can
    /// never be complete, so dropping an unrecognized value-bearing flag is the
    /// unsafe default. Include any value-bearing `-` token unless it is explicitly
    /// known to be benign.
    static func scopeKey(runner: String, tokens: [String]) -> String {
        var parts: [String] = []
        let args = Array(tokens.dropFirst())
        var index = 0
        while index < args.count {
            let token = args[index]
            guard token.hasPrefix("-") else {
                parts.append(token)
                index += 1
                continue
            }

            if token == "--" {
                index += 1
                continue
            }

            if let (flag, value) = attachedFlagValue(token) {
                if !benignNonSelectingFlags.contains(flag) {
                    parts.append("\(flag)=\(value)")
                }
                index += 1
                continue
            }

            if benignNonSelectingFlags.contains(token) {
                index += 1
                continue
            }

            if index + 1 < args.count, !args[index + 1].hasPrefix("-") {
                parts.append("\(token)=\(args[index + 1])")
                index += 2
                continue
            }

            parts.append(token)
            index += 1
        }
        return "\(runner)|\(parts.joined(separator: " "))"
    }

    /// Parses attached-value flags into `(base flag, value)`.
    static func attachedFlagValue(_ token: String) -> (flag: String, value: String)? {
        if token.hasPrefix("--"), let eq = token.firstIndex(of: "=") {
            let flag = String(token[token.startIndex..<eq])
            let value = String(token[token.index(after: eq)...])
            return value.isEmpty ? nil : (flag, value)
        }
        if token.hasPrefix("-"), !token.hasPrefix("--"), let eq = token.firstIndex(of: "=") {
            let flag = String(token[token.startIndex..<eq])
            let value = String(token[token.index(after: eq)...])
            return value.isEmpty || flag.count < 2 ? nil : (flag, value)
        }
        if token.hasPrefix("-"), !token.hasPrefix("--"), token.count > 2 {
            let flag = String(token.prefix(2))
            let value = String(token.dropFirst(2))
            if !value.isEmpty { return (flag, value) }
        }
        return nil
    }
}
