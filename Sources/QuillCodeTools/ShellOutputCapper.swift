import Foundation

/// Bounds shell command output so a chatty command (a big test log, a `find`) can't blow the model's
/// context window on an unattended run. Truncates from the FRONT (keeps the tail) because for a shell
/// run the ending — the final status, the error, the summary line — is what matters most. When it
/// trims, it prepends an honest note so the model knows output was dropped.
///
/// `maxBytes` bounds the kept PAYLOAD; the one-line note is metadata prepended after capping, so the
/// returned text can exceed `maxBytes` by the note's length.
public enum ShellOutputCapper {
    public static let defaultMaxLines = 2000
    public static let defaultMaxBytes = 50_000

    public static func cap(
        _ text: String,
        maxLines: Int = defaultMaxLines,
        maxBytes: Int = defaultMaxBytes
    ) -> (text: String, truncated: Bool) {
        // A trailing newline TERMINATES the last line — it is not an extra empty line. Count the way
        // `wc -l` does, so output exactly at the limit isn't truncated one line early (shell output
        // almost always ends in a newline).
        let hadTrailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if hadTrailingNewline {
            lines.removeLast()
        }
        let totalLines = text.isEmpty ? 0 : lines.count
        let totalBytes = text.utf8.count
        guard totalLines > maxLines || totalBytes > maxBytes else {
            return (text, false)
        }

        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        var kept = lines.joined(separator: "\n")
        if hadTrailingNewline, !kept.isEmpty {
            kept += "\n"
        }

        // Byte ceiling on the already line-trimmed tail: keep the last maxBytes bytes, then drop any
        // leading UTF-8 continuation bytes (0b10xxxxxx) so the cut lands on a codepoint boundary — a
        // raw byte cut can start mid-scalar and would decode to U+FFFD garbage at the head of the tail.
        if kept.utf8.count > maxBytes {
            var bytes = Array(kept.utf8.suffix(maxBytes))
            while let first = bytes.first, first & 0b1100_0000 == 0b1000_0000 {
                bytes.removeFirst()
            }
            kept = String(decoding: bytes, as: UTF8.self)
        }

        let note = "[output truncated — showing the tail; \(totalLines) line\(totalLines == 1 ? "" : "s"), \(totalBytes) bytes total]\n"
        return (note + kept, true)
    }
}
