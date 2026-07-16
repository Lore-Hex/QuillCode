import Foundation

struct SSHConfigDirective: Sendable, Hashable {
    var keyword: String
    var arguments: [String]
}

enum SSHConfigParser {
    static func directives(in text: String) -> [SSHConfigDirective] {
        text.split(whereSeparator: \Character.isNewline).compactMap { rawLine in
            directive(in: String(rawLine))
        }
    }

    static func concreteHostAliases(in text: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var aliases: [String] = []
        var seen: Set<String> = []

        for directive in directives(in: text) where directive.keyword == "host" {
            for alias in directive.arguments where isConcreteHostAlias(alias) {
                let key = alias.lowercased()
                guard seen.insert(key).inserted else { continue }
                aliases.append(alias)
                if aliases.count == limit {
                    return aliases
                }
            }
        }
        return aliases
    }

    static func includePatterns(in text: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var patterns: [String] = []
        for directive in directives(in: text) where directive.keyword == "include" {
            for argument in directive.arguments {
                patterns.append(argument)
                if patterns.count == limit {
                    return patterns
                }
            }
        }
        return patterns
    }

    static func isConcreteHostAlias(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 255,
              !value.hasPrefix("-"),
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains(where: { $0.isWhitespace || $0.isNewline || $0.isASCIIControl })
        else {
            return false
        }
        return !value.contains(where: { "*!?[".contains($0) })
    }

    private static func directive(in line: String) -> SSHConfigDirective? {
        guard line.utf8.count <= 16_384 else { return nil }
        var tokens = tokens(in: line)
        guard !tokens.isEmpty else { return nil }

        if let separator = tokens[0].firstIndex(of: "=") {
            let keyword = String(tokens[0][..<separator])
            let value = String(tokens[0][tokens[0].index(after: separator)...])
            tokens[0] = keyword
            if !value.isEmpty {
                tokens.insert(value, at: 1)
            }
        }
        normalizeSeparatedAssignment(in: &tokens)

        let keyword = tokens.removeFirst().lowercased()
        guard !keyword.isEmpty, !tokens.isEmpty else { return nil }
        return SSHConfigDirective(keyword: keyword, arguments: tokens)
    }

    private static func normalizeSeparatedAssignment(in tokens: inout [String]) {
        guard tokens.count > 1 else { return }
        if tokens[1] == "=" {
            tokens.remove(at: 1)
            return
        }
        guard tokens[1].hasPrefix("=") else { return }
        let value = String(tokens[1].dropFirst())
        if value.isEmpty {
            tokens.remove(at: 1)
        } else {
            tokens[1] = value
        }
    }

    private static func tokens(in line: String) -> [String] {
        var result: [String] = []
        var token = ""
        var quote: Character?
        var isEscaping = false

        func flush() {
            guard !token.isEmpty else { return }
            result.append(token)
            token = ""
        }

        for character in line {
            if isEscaping {
                token.append(character)
                isEscaping = false
                continue
            }
            if character == "\\" {
                isEscaping = true
                continue
            }
            if quote != nil {
                if character == quote {
                    quote = nil
                } else {
                    token.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                break
            } else if character.isWhitespace {
                flush()
            } else {
                token.append(character)
            }
        }
        if isEscaping {
            token.append("\\")
        }
        flush()
        return result
    }
}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.allSatisfy { $0.value < 0x20 || $0.value == 0x7f }
    }
}
