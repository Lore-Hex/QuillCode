import Foundation

/// Content-type classification and hostile-input-safe text decoding for `host.web.fetch`.
/// Decoding never fails: unknown or lying charsets fall back to lossy UTF-8 (invalid bytes
/// become U+FFFD), matching the "convert what we can, never explode" contract of the tool.
enum WebFetchResponseDecoder {
    enum ContentClass: Equatable {
        /// HTML that should be converted to markdown.
        case html
        /// Markdown or plain text that passes through untouched.
        case passthroughText
        /// Some other textual type (JSON, XML, JS, …) that also passes through.
        case otherText
        /// Binary or unknown-binary content the tool refuses to return.
        case refused(reportedType: String)
    }

    /// Classifies a Content-Type header value; when it is missing, sniffs the body prefix.
    static func classify(contentType: String?, bodyPrefix: Data) -> ContentClass {
        guard let contentType, !mimeType(of: contentType).isEmpty else {
            return sniff(bodyPrefix: bodyPrefix)
        }
        let mime = mimeType(of: contentType)
        switch mime {
        case "text/html", "application/xhtml+xml":
            return .html
        case "text/markdown", "text/x-markdown", "text/plain":
            return .passthroughText
        default:
            break
        }
        if mime.hasPrefix("text/") {
            return .otherText
        }
        if textualApplicationTypes.contains(mime)
            || mime.hasSuffix("+json") || mime.hasSuffix("+xml") {
            return .otherText
        }
        return .refused(reportedType: mime)
    }

    /// The `type/subtype` portion of a Content-Type value, lowercased, parameters dropped.
    /// Empty subsequences are kept so a malformed ";charset=utf-8" yields "" rather than
    /// promoting the parameter into the mime type.
    static func mimeType(of contentType: String) -> String {
        (contentType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// The `charset` parameter of a Content-Type value, if present.
    static func charset(of contentType: String?) -> String? {
        guard let contentType else {
            return nil
        }
        for parameter in contentType.split(separator: ";").dropFirst() {
            let parts = parameter.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset"
            else {
                continue
            }
            let value = parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .lowercased()
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Decodes body bytes to text: honor the declared charset when we support it, sniff a
    /// `<meta charset>` for HTML when the header stays silent, and otherwise decode as lossy
    /// UTF-8. NUL bytes are stripped so binary-ish content cannot smuggle terminators.
    static func decode(_ data: Data, declaredCharset: String?, sniffHTMLMeta: Bool) -> String {
        var body = data
        // A UTF-8 BOM is decoration; a UTF-16 BOM decides the encoding outright.
        if body.starts(with: [0xEF, 0xBB, 0xBF]) {
            body = body.dropFirst(3)
        } else if body.starts(with: [0xFF, 0xFE]) || body.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: body, encoding: .utf16) {
                return stripNULs(text)
            }
        }
        var charset = declaredCharset
        if charset == nil, sniffHTMLMeta {
            charset = sniffMetaCharset(in: body)
        }
        let text = decode(body, charset: charset ?? "utf-8")
        return stripNULs(text)
    }

    // MARK: - Internals

    private static func decode(_ data: Data, charset: String) -> String {
        let normalized = charset.lowercased().trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "utf-8", "utf8", "us-ascii", "ascii", "":
            return String(decoding: data, as: UTF8.self)
        case "iso-8859-1", "iso8859-1", "latin1", "latin-1", "l1", "cp819":
            return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
        case "windows-1252", "cp1252", "x-cp1252":
            return String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
        case "iso-8859-2", "latin2":
            return String(data: data, encoding: .isoLatin2) ?? String(decoding: data, as: UTF8.self)
        case "utf-16", "utf16":
            return String(data: data, encoding: .utf16) ?? String(decoding: data, as: UTF8.self)
        case "utf-16le":
            return String(data: data, encoding: .utf16LittleEndian) ?? String(decoding: data, as: UTF8.self)
        case "utf-16be":
            return String(data: data, encoding: .utf16BigEndian) ?? String(decoding: data, as: UTF8.self)
        case "shift_jis", "shift-jis", "sjis", "x-sjis":
            return String(data: data, encoding: .shiftJIS) ?? String(decoding: data, as: UTF8.self)
        case "euc-jp":
            return String(data: data, encoding: .japaneseEUC) ?? String(decoding: data, as: UTF8.self)
        case "iso-2022-jp":
            return String(data: data, encoding: .iso2022JP) ?? String(decoding: data, as: UTF8.self)
        default:
            // Unknown charset: lossy UTF-8 beats failing — replacement characters are honest.
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// Best-effort `<meta charset="…">` / `<meta http-equiv … content="…charset=…">` sniff in
    /// the first 1024 bytes, the way browsers do when the header does not say.
    private static func sniffMetaCharset(in body: Data) -> String? {
        let prefix = String(decoding: body.prefix(1024), as: UTF8.self).lowercased()
        guard let metaRange = prefix.range(of: "charset=") else {
            return nil
        }
        var value = ""
        var iterator = prefix[metaRange.upperBound...].makeIterator()
        var pendingQuote: Character?
        while let character = iterator.next(), value.count < 40 {
            if value.isEmpty, character == "\"" || character == "'" {
                pendingQuote = character
                continue
            }
            if let quote = pendingQuote {
                if character == quote {
                    break
                }
            } else if character == "\"" || character == "'" || character == ">" || character == "/"
                        || character == ";" || character.isWhitespace {
                break
            }
            value.append(character)
        }
        let charset = value.trimmingCharacters(in: .whitespaces)
        return charset.isEmpty ? nil : charset
    }

    private static func sniff(bodyPrefix: Data) -> ContentClass {
        let sample = String(decoding: bodyPrefix.prefix(512), as: UTF8.self).lowercased()
        if sample.contains("<!doctype html") || sample.contains("<html") {
            return .html
        }
        if bodyPrefix.prefix(512).contains(0) {
            return .refused(reportedType: "unknown binary content")
        }
        return .passthroughText
    }

    private static func stripNULs(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return text
        }
        return String(text.unicodeScalars.filter { $0.value != 0 }.map(Character.init))
    }

    private static let textualApplicationTypes: Set<String> = [
        "application/json", "application/xml", "application/javascript",
        "application/ecmascript", "application/x-javascript", "application/yaml",
        "application/x-yaml", "application/toml", "application/x-ndjson",
        "application/x-www-form-urlencoded", "application/sql", "application/graphql",
        "application/rtf", "application/csv", "application/x-sh", "application/wasm-text",
        "application/atom+xml", "application/rss+xml"
    ]
}
