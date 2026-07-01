import Foundation

/// Bounds shell command output so a chatty command (a big test log, a `find`) can't blow the model's
/// context window on an unattended run. Truncates from the FRONT (keeps the tail) because for a shell
/// run the ending — the final status, the error, the summary line — is what matters most. When it
/// trims, it prepends an honest note so the model knows output was dropped.
public enum ShellOutputCapper {
    public static let defaultMaxLines = 2000
    public static let defaultMaxBytes = 50_000

    public static func cap(
        _ text: String,
        maxLines: Int = defaultMaxLines,
        maxBytes: Int = defaultMaxBytes
    ) -> (text: String, truncated: Bool) {
        let totalLines = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        let totalBytes = text.utf8.count
        guard totalLines > maxLines || totalBytes > maxBytes else {
            return (text, false)
        }

        var lines = text.components(separatedBy: "\n")
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        var kept = lines.joined(separator: "\n")

        // Byte ceiling on the already line-trimmed tail: keep the last maxBytes bytes. Decoding a tail
        // that may start mid-codepoint is tolerated (the leading partial byte becomes U+FFFD).
        if kept.utf8.count > maxBytes {
            kept = String(decoding: Data(kept.utf8.suffix(maxBytes)), as: UTF8.self)
        }

        let note = "[output truncated — showing the tail; \(totalLines) line\(totalLines == 1 ? "" : "s"), \(totalBytes) bytes total]\n"
        return (note + kept, true)
    }
}
