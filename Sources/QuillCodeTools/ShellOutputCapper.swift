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
        var accumulator = ShellOutputAccumulator(maxLines: maxLines, maxBytes: maxBytes)
        accumulator.append(text)
        return accumulator.result
    }
}

/// Incrementally retains the same bounded tail as ``ShellOutputCapper`` without first buffering an
/// arbitrarily large command response. This is used by long-lived streaming shells where collecting
/// the complete output would defeat the cap's memory-safety guarantee.
public struct ShellOutputAccumulator: Sendable {
    private let maxLines: Int
    private let maxBytes: Int
    private var tail = Data()
    private var totalBytes = 0
    private var newlineCount = 0
    private var hasContent = false
    private var endsWithNewline = false

    public init(
        maxLines: Int = ShellOutputCapper.defaultMaxLines,
        maxBytes: Int = ShellOutputCapper.defaultMaxBytes
    ) {
        self.maxLines = max(0, maxLines)
        self.maxBytes = max(0, maxBytes)
    }

    public mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        let data = Data(text.utf8)
        hasContent = true
        totalBytes += data.count
        newlineCount += data.reduce(into: 0) { count, byte in
            if byte == 0x0A { count += 1 }
        }
        endsWithNewline = data.last == 0x0A
        tail.append(data)
        if tail.count > maxBytes {
            tail = Data(tail.suffix(maxBytes))
        }
    }

    public var text: String {
        result.text
    }

    public var result: (text: String, truncated: Bool) {
        guard hasContent else { return ("", false) }
        let totalLines = newlineCount + (endsWithNewline ? 0 : 1)
        var bytes = Array(tail)
        while let first = bytes.first, first & 0b1100_0000 == 0b1000_0000 {
            bytes.removeFirst()
        }
        var kept = String(decoding: bytes, as: UTF8.self)
        let hadTrailingNewline = kept.hasSuffix("\n")
        var lines = kept.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
            kept = lines.joined(separator: "\n")
            if hadTrailingNewline, !kept.isEmpty { kept += "\n" }
        }

        guard totalLines > maxLines || totalBytes > maxBytes else { return (kept, false) }
        let note = "[output truncated — showing the tail; \(totalLines) line\(totalLines == 1 ? "" : "s"), \(totalBytes) bytes total]\n"
        return (note + kept, true)
    }
}
