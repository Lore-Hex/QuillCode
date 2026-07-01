import Foundation

/// The byte-level encoding traits of a text file that a full-content rewrite must preserve: a leading
/// UTF-8 BOM and the dominant line-ending style. Without this, writing model-authored content (always
/// bare-LF, no BOM) over a Windows-authored file silently flips every line to LF and drops the BOM —
/// turning a one-line edit into a whole-file diff.
public enum FileLineEnding: Sendable, Hashable {
    case lf
    case crlf

    var terminator: String { self == .crlf ? "\r\n" : "\n" }
}

public struct FileEncodingStyle: Sendable, Hashable {
    public var hasBOM: Bool
    public var lineEnding: FileLineEnding

    public init(hasBOM: Bool, lineEnding: FileLineEnding) {
        self.hasBOM = hasBOM
        self.lineEnding = lineEnding
    }

    /// What a brand-new file gets: bare UTF-8, LF, no BOM.
    public static let `default` = FileEncodingStyle(hasBOM: false, lineEnding: .lf)
}

public enum FileEncodingPreservation {
    static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Detect the BOM + dominant line ending of an existing file's raw bytes.
    public static func detect(_ data: Data) -> FileEncodingStyle {
        let hasBOM = data.starts(with: utf8BOM)
        let body = hasBOM ? data.dropFirst(utf8BOM.count) : data[...]
        return FileEncodingStyle(hasBOM: hasBOM, lineEnding: detectLineEnding(body))
    }

    /// Count CRLF vs bare-LF newlines; the majority wins. No newlines (or a tie) defaults to LF, so a
    /// single-line file or an empty file is treated as LF rather than guessing CRLF.
    static func detectLineEnding<S: Sequence>(_ bytes: S) -> FileLineEnding where S.Element == UInt8 {
        var crlf = 0
        var lf = 0
        var previous: UInt8 = 0
        for byte in bytes {
            if byte == 0x0A {   // \n
                if previous == 0x0D { crlf += 1 } else { lf += 1 }
            }
            previous = byte
        }
        return crlf > lf ? .crlf : .lf
    }

    /// Encode model-authored content (canonically bare-LF) as bytes matching the target file's style:
    /// re-apply CRLF if the original used it, and re-prepend the BOM if the original had one.
    public static func apply(_ content: String, style: FileEncodingStyle) -> Data {
        // Canonicalize any incoming CRLF to LF first so re-lining is idempotent and never yields CRCRLF.
        let canonical = content.replacingOccurrences(of: "\r\n", with: "\n")
        let relined = style.lineEnding == .crlf
            ? canonical.replacingOccurrences(of: "\n", with: "\r\n")
            : canonical
        var data = Data()
        if style.hasBOM { data.append(contentsOf: utf8BOM) }
        data.append(contentsOf: relined.utf8)
        return data
    }

    /// Strip a leading BOM and normalize CRLF→LF for on-screen rendering, so the numbered read view is
    /// not polluted by a U+FEFF on line 1 or a trailing `\r` on every line. Does not alter the file.
    ///
    /// Lone CR (classic pre-OSX Mac endings) is also mapped to LF — CRLF first so it never doubles —
    /// otherwise a CR-only file renders as ONE numbered line with embedded control characters.
    /// (Display only: `detect`/`apply` deliberately stay CRLF-vs-LF; rewriting a CR-only file
    /// normalizes it to LF, an acceptable edge for a 25-year-dead convention.)
    public static func normalizeForDisplay(_ text: String) -> String {
        var result = text
        if result.first == "\u{FEFF}" { result.removeFirst() }
        return result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
