import Foundation

/// Extracts the file paths a unified diff's headers reference, handling git's C-style quoted
/// paths (`core.quotepath` quotes non-ASCII, double quotes, backslashes, and control characters
/// as `"a/r\303\251sum\303\251.txt"`) and `rename`/`copy` headers.
///
/// `diff --git a/... b/...` lines are parsed as a fallback for binary patches, which may not
/// include `---`/`+++` content headers. Git quotes paths with spaces/special characters there, so
/// the token parser handles both plain and C-style quoted path tokens.
enum DiffHeaderPathParser {
    /// The workspace-relative paths a unified diff touches: `---`/`+++` paths with the `a/`/`b/`
    /// prefix stripped plus rename/copy header paths (which carry no prefix), `/dev/null`
    /// excluded, deduplicated in order of first appearance.
    static func targetPaths(in patch: String) -> [String] {
        var seen = Set<String>()
        var orderedPaths: [String] = []
        for line in patch.components(separatedBy: .newlines) {
            for raw in paths(in: line) where raw != "/dev/null" {
                let path = strippingDiffPrefix(raw)
                if seen.insert(path).inserted {
                    orderedPaths.append(path)
                }
            }
        }
        return orderedPaths
    }

    /// Every path a diff metadata line names. Most headers name one path; `diff --git` names old
    /// and new paths and is needed for binary patches that have no `---`/`+++` lines.
    static func paths(in line: String) -> [String] {
        if let paths = diffGitPaths(in: line) {
            return paths
        }
        return headerPath(in: line).map { [$0] } ?? []
    }

    /// The single path a `---` / `+++` / `rename from|to` / `copy from|to` header line names,
    /// unquoted but with any `a/`/`b/` prefix preserved. nil for any other line.
    static func headerPath(in line: String) -> String? {
        for prefix in ["--- ", "+++ "] where line.hasPrefix(prefix) {
            return pathToken(String(line.dropFirst(prefix.count)))
        }
        for prefix in ["rename from ", "rename to ", "copy from ", "copy to "] where line.hasPrefix(prefix) {
            return pathToken(String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func diffGitPaths(in line: String) -> [String]? {
        guard line.hasPrefix("diff --git ") else { return nil }
        let rest = line.dropFirst("diff --git ".count)
        if rest.first != "\"", let secondPathRange = rest.range(of: " b/", options: .backwards) {
            let first = String(rest[..<secondPathRange.lowerBound])
            let second = String(rest[rest.index(after: secondPathRange.lowerBound)...])
            return [first, second]
        }
        guard let first = pathTokenAndRemainder(in: rest),
              let second = pathTokenAndRemainder(in: first.remainder)
        else { return [] }
        return [first.path, second.path]
    }

    static func strippingDiffPrefix(_ path: String) -> String {
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    private static func pathTokenAndRemainder(in text: Substring) -> (path: String, remainder: Substring)? {
        let trimmed = text.drop(while: \.isWhitespace)
        guard let first = trimmed.first else { return nil }
        if first == "\"" {
            return quotedPathTokenAndRemainder(in: trimmed)
        }
        let tokenEnd = trimmed.firstIndex(where: \.isWhitespace) ?? trimmed.endIndex
        let token = String(trimmed[..<tokenEnd])
        return (token, trimmed[tokenEnd...])
    }

    private static func quotedPathTokenAndRemainder(in text: Substring) -> (path: String, remainder: Substring)? {
        var index = text.index(after: text.startIndex)
        var escaping = false
        while index < text.endIndex {
            let character = text[index]
            if escaping {
                escaping = false
                index = text.index(after: index)
                continue
            }
            if character == "\\" {
                escaping = true
                index = text.index(after: index)
                continue
            }
            if character == "\"" {
                let token = String(text[...index])
                return (unquote(leading: token) ?? token, text[text.index(after: index)...])
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// A header line's path portion: a C-style quoted string is unquoted (anything after the
    /// closing quote ignored); an unquoted path runs to the first tab (git itself never appends
    /// a timestamp, but classic unified diffs do, separated by a tab). A malformed quoted token
    /// is kept verbatim so a safety check still sees *something* to reject rather than nothing.
    static func pathToken(_ rest: String) -> String {
        if rest.hasPrefix("\"") {
            return unquote(leading: rest) ?? rest
        }
        return rest.split(separator: "\t").first.map(String.init) ?? rest
    }

    /// Decodes the C-style quoted string at the START of `text` (git's `core.quotepath`
    /// encoding): `\a \b \f \n \r \t \v \\ \"` plus 1–3 digit octal byte escapes. Returns nil
    /// when the token is unterminated, contains a bad escape, or is not valid UTF-8.
    static func unquote(leading text: String) -> String? {
        let bytes = Array(text.utf8)
        guard bytes.first == UInt8(ascii: "\"") else { return nil }
        var decoded: [UInt8] = []
        var index = 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                return String(bytes: decoded, encoding: .utf8)
            }
            if byte != UInt8(ascii: "\\") {
                decoded.append(byte)
                index += 1
                continue
            }
            index += 1
            guard index < bytes.count else { return nil }
            let escape = bytes[index]
            switch escape {
            case UInt8(ascii: "a"): decoded.append(0x07); index += 1
            case UInt8(ascii: "b"): decoded.append(0x08); index += 1
            case UInt8(ascii: "f"): decoded.append(0x0C); index += 1
            case UInt8(ascii: "n"): decoded.append(0x0A); index += 1
            case UInt8(ascii: "r"): decoded.append(0x0D); index += 1
            case UInt8(ascii: "t"): decoded.append(0x09); index += 1
            case UInt8(ascii: "v"): decoded.append(0x0B); index += 1
            case UInt8(ascii: "\\"), UInt8(ascii: "\""): decoded.append(escape); index += 1
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var value = 0
                var digits = 0
                while digits < 3, index < bytes.count,
                      (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(bytes[index]) {
                    value = value * 8 + Int(bytes[index] - UInt8(ascii: "0"))
                    digits += 1
                    index += 1
                }
                guard value <= 255 else { return nil }
                decoded.append(UInt8(value))
            default:
                return nil
            }
        }
        return nil // unterminated
    }
}
