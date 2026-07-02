import Foundation

/// Bounds `host.web.fetch` output the way `ShellOutputCapper` bounds shell output, but keeps
/// the HEAD instead of the tail: for a fetched page the title, intro, and leading sections are
/// what matter, so truncation drops the end and appends an honest note.
///
/// `maxBytes` bounds the kept PAYLOAD; the one-line note is metadata appended after capping.
public enum WebFetchMarkdownCapper {
    public static let defaultMaxLines = 2000
    public static let defaultMaxBytes = 48_000

    public static func cap(
        _ text: String,
        maxLines: Int = defaultMaxLines,
        maxBytes: Int = defaultMaxBytes
    ) -> (text: String, truncated: Bool) {
        let totalBytes = text.utf8.count
        let hadTrailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if hadTrailingNewline {
            lines.removeLast()
        }
        let totalLines = text.isEmpty ? 0 : lines.count
        guard totalLines > maxLines || totalBytes > maxBytes else {
            return (text, false)
        }

        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
        }
        var kept = lines.joined(separator: "\n")

        // Byte ceiling on the already line-trimmed head: keep the first maxBytes bytes, then
        // drop trailing UTF-8 continuation bytes so the cut lands on a codepoint boundary.
        if kept.utf8.count > maxBytes {
            var bytes = Array(kept.utf8.prefix(maxBytes))
            while let last = bytes.last, last & 0b1100_0000 == 0b1000_0000 {
                bytes.removeLast()
            }
            // The byte we cut at may be the LEAD byte of a multi-byte scalar; drop it too.
            if let last = bytes.last, last & 0b1000_0000 == 0b1000_0000 {
                bytes.removeLast()
            }
            kept = String(decoding: bytes, as: UTF8.self)
        }

        let note = "\n\n[content truncated — showing the beginning; \(totalLines) line\(totalLines == 1 ? "" : "s"), \(totalBytes) bytes total]"
        return (kept + note, true)
    }
}
