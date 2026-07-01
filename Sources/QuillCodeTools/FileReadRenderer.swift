import Foundation

/// Renders a file's text the way a coding model relies on it: with 1-based line numbers (so it can
/// target edits and reference lines precisely — the same `cat -n`-style presentation the models are
/// trained on), an optional `[offset, offset+limit)` window so a huge file doesn't blow the context,
/// and per-line truncation so one minified/generated line can't either. Pure + testable.
public enum FileReadRenderer {
    public static let defaultMaxLines = 2000
    public static let defaultMaxLineLength = 2000

    public static func render(
        _ text: String,
        offset: Int? = nil,
        limit: Int? = nil,
        maxLines: Int = defaultMaxLines,
        maxLineLength: Int = defaultMaxLineLength
    ) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        // A file ending in a newline splits to a trailing "" — drop it so the count is the real one.
        if text.hasSuffix("\n"), lines.last == "" { lines.removeLast() }

        let total = lines.count
        guard total > 0 else { return "[empty file]" }

        let start = max(1, offset ?? 1)
        guard start <= total else {
            return "[file has \(total) line\(total == 1 ? "" : "s"); offset \(start) is past the end]"
        }
        let windowLimit = max(1, min(limit ?? maxLines, maxLines))
        let end = min(total, start + windowLimit - 1)
        let width = String(end).count

        var rendered: [String] = []
        rendered.reserveCapacity(end - start + 1)
        for i in start...end {
            let raw = lines[i - 1]
            let line = raw.count > maxLineLength
                ? String(raw.prefix(maxLineLength)) + "… [line truncated]"
                : raw
            let number = String(i)
            let padding = String(repeating: " ", count: max(0, width - number.count))
            rendered.append("\(padding)\(number)\t\(line)")
        }

        var body = rendered.joined(separator: "\n")
        if end < total {
            body += "\n\n[showing lines \(start)–\(end) of \(total); pass offset=\(end + 1) to read more]"
        } else if start > 1 {
            body += "\n\n[showing lines \(start)–\(end) of \(total)]"
        }
        return body
    }

    /// Whether the data is (probably) not text — a NUL byte in the head is the classic binary signal,
    /// and anything that is not valid UTF-8 is treated as binary too. Keeps the agent from poisoning its
    /// context with a JPEG or an object file.
    public static func isProbablyBinary(_ data: Data) -> Bool {
        if data.prefix(8192).contains(0) { return true }
        return String(data: data, encoding: .utf8) == nil
    }

    /// A short, honest one-liner for a binary/image file instead of erroring or dumping garbage.
    public static func binaryDescription(_ data: Data, fileName: String) -> String {
        "[\(mediaKind(data)) file: \(fileName), \(data.count) byte\(data.count == 1 ? "" : "s") — not shown as text]"
    }

    private static func mediaKind(_ data: Data) -> String {
        let head = Array(data.prefix(12))
        func starts(_ bytes: [UInt8]) -> Bool { head.count >= bytes.count && Array(head.prefix(bytes.count)) == bytes }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "PNG image" }
        if starts([0xFF, 0xD8, 0xFF]) { return "JPEG image" }
        if starts([0x47, 0x49, 0x46, 0x38]) { return "GIF image" }
        if starts([0x25, 0x50, 0x44, 0x46]) { return "PDF" }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return "zip/archive" }
        return "binary"
    }
}
