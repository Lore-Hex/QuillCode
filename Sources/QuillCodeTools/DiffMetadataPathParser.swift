import Foundation

enum DiffMetadataPathParser {
    static func paths(in line: String) -> [String] {
        if line.hasPrefix("diff --git ") {
            return pathsInDiffGitHeader(String(line.dropFirst("diff --git ".count)))
        }
        guard line.hasPrefix("--- ") || line.hasPrefix("+++ ") else {
            return []
        }
        return line
            .dropFirst(4)
            .split(separator: "\t")
            .first
            .map { [String($0)] } ?? []
    }

    static func normalizedPath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("\"") {
            path.removeFirst()
        }
        if path.hasSuffix("\"") {
            path.removeLast()
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path.removeFirst(2)
        }
        return path
    }

    private static func pathsInDiffGitHeader(_ header: String) -> [String] {
        if header.hasPrefix("\"") {
            return quotedPaths(in: header)
        }
        guard let secondPathRange = header.range(of: " b/") else {
            return header.split(separator: " ").map(String.init)
        }
        let first = String(header[..<secondPathRange.lowerBound])
        let second = String(header[header.index(after: secondPathRange.lowerBound)...])
        return [first, second]
    }

    private static func quotedPaths(in header: String) -> [String] {
        var paths: [String] = []
        var current = ""
        var isInQuote = false
        var isEscaped = false

        for character in header {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                if isInQuote {
                    paths.append(current)
                    current = ""
                }
                isInQuote.toggle()
                continue
            }
            if isInQuote {
                current.append(character)
            }
        }
        return paths
    }
}
