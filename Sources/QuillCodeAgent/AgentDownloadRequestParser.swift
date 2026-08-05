import Foundation

enum AgentDownloadRequestParser {
    static func shellCommand(from request: String) -> String? {
        let lower = request.lowercased()
        let downloadTerms = [
            "download ",
            "save ",
            "fetch "
        ]
        guard downloadTerms.contains(where: { lower.contains($0) }),
              let target = extractDownloadTarget(from: request)
        else {
            return nil
        }

        let url = normalizedWebURLString(target)
        let path = extractRequestedDownloadPath(from: request) ?? "downloads/\(downloadFileName(for: url))"
        let parentDirectory = parentDirectory(for: path)
        return [
            "mkdir -p \(shellSingleQuoted(parentDirectory))",
            "curl -L --fail --silent --show-error --output \(shellSingleQuoted(path)) \(shellSingleQuoted(url))",
            "ls -lh \(shellSingleQuoted(path))"
        ].joined(separator: " && ")
    }

    private static func extractDownloadTarget(from request: String) -> String? {
        let tokens = downloadTokens(in: request)
        // The file the user asked us to WRITE is never the thing to fetch. "Save it as
        // transactions.csv" used to yield `curl https://transactions.csv` as the run's first
        // action (live: seen as the opening step of an office task in the desktop app).
        let destination = extractRequestedDownloadPath(from: request)?.lowercased()

        if let token = tokens.first(where: {
            looksLikeDownloadSource($0) && $0.lowercased() != destination
        }) {
            return token
        }
        if let quoted = AgentRequestTextScanner.backtickQuotedValues(in: request).first(where: looksLikeDownloadSource) {
            return quoted
        }
        return AgentRequestTextScanner.backtickQuotedValues(in: request).first(where: looksLikeBrowserTarget)
    }

    private static func downloadTokens(in request: String) -> [String] {
        let tokenSeparators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "`\"'(),<>[]{}"))
        return request
            .components(separatedBy: tokenSeparators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".:;!?")) }
            .filter { !$0.isEmpty }
    }

    private static func looksLikeBrowserTarget(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("file://")
            || lower.hasPrefix("localhost")
            || lower.hasPrefix("127.0.0.1")
            || lower.hasPrefix("./")
            || lower.hasPrefix("/")
            || lower.hasSuffix(".html")
            || lower.hasSuffix(".htm")
            || (lower.contains(".") && !lower.contains("@"))
    }

    private static func looksLikeDownloadSource(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://") {
            return true
        }
        guard !lower.hasPrefix("./"),
              !lower.hasPrefix("/"),
              !lower.contains("@")
        else {
            return false
        }
        let firstPathComponent = lower.split(separator: "/", maxSplits: 1).first ?? ""
        guard firstPathComponent.contains(".") else { return false }
        // A bare local filename is not a host. `report.md`, `transactions.csv`, `deck.pptx` all
        // "contain a dot", but their final component is a FILE EXTENSION, not a TLD — treating
        // them as download sources fabricates `https://<filename>` and fires a doomed curl.
        // A real bare-host source ("example.com/data.csv") keeps its host in the first component.
        let suffix = firstPathComponent.split(separator: ".").last.map(String.init) ?? ""
        return !localFileExtensions.contains(suffix)
    }

    /// Extensions that mark a token as a local artifact rather than a hostname. Deliberately the
    /// document/data/media types office tasks name as OUTPUTS; unknown suffixes still pass so a
    /// genuine `example.io/report` style source is unaffected.
    private static let localFileExtensions: Set<String> = [
        "csv", "tsv", "md", "markdown", "txt", "text", "log", "json", "yaml", "yml", "xml",
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "odt", "ods",
        "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "mp3", "mp4", "mov", "wav",
        "zip", "tar", "gz", "sql", "db", "sqlite", "ics", "vcf",
    ]

    private static func extractRequestedDownloadPath(from request: String) -> String? {
        if let quotedPath = AgentRequestTextScanner.backtickQuotedValues(in: request)
            .compactMap(safeRelativeWorkspacePath)
            .first {
            return quotedPath
        }

        let lower = request.lowercased()
        for marker in [" into ", " to ", " as "] {
            guard let range = lower.range(of: marker) else { continue }
            let suffix = String(request[range.upperBound...])
            let token = suffix
                .split(whereSeparator: { $0.isWhitespace || "\"'(),<>[]{}".contains($0) })
                .first
                .map(String.init)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "`.:;!?"))
            if let token, let safePath = safeRelativeWorkspacePath(token) {
                return safePath
            }
        }
        return nil
    }

    private static func safeRelativeWorkspacePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentRequestPathGuard.isSafeWorkspaceRelativePath(trimmed) ? trimmed : nil
    }

    private static func parentDirectory(for path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        let parent = path[..<slash]
        return parent.isEmpty ? "." : String(parent)
    }

    private static func normalizedWebURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://")
            || trimmed.lowercased().hasPrefix("https://")
            || trimmed.lowercased().hasPrefix("file://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private static func downloadFileName(for urlString: String) -> String {
        let url = URL(string: urlString)
        let host = url?.host?.lowercased().replacingOccurrences(of: "www.", with: "") ?? "download"
        let lastComponent = url?.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = lastComponent.contains(".") ? lastComponent : "\(host).html"
        let sanitized = base.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-" || character == "_"
                ? character
                : "-"
        }
        let filename = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return filename.isEmpty ? "download.html" : filename
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
