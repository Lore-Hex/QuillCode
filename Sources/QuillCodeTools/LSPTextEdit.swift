import Foundation

/// A single `TextEdit` from a formatting response: replace the `range` with `newText`.
public struct LSPTextEdit: Equatable, Sendable {
    public var range: LSPRange
    public var newText: String

    public init(range: LSPRange, newText: String) {
        self.range = range
        self.newText = newText
    }

    public static func parse(_ any: Any?) -> LSPTextEdit? {
        guard let object = any as? [String: Any],
              let range = LSPRange.parse(object["range"]),
              let newText = object["newText"] as? String
        else { return nil }
        return LSPTextEdit(range: range, newText: newText)
    }

    public static func parseList(_ any: Any?) -> [LSPTextEdit] {
        guard let array = any as? [[String: Any]] else { return [] }
        return array.compactMap { parse($0) }
    }
}

/// Applies LSP text edits to a document string. LSP positions are 0-based `(line, UTF-16 code unit)`
/// offsets; the spec guarantees edits within one response do not overlap, so we sort them
/// end-to-start and splice each in turn — applying from the back keeps earlier positions valid.
///
/// Returns `nil` when any edit references a position outside the document (a malformed server
/// response), so the caller keeps the original file untouched rather than writing corrupted text.
public enum LSPEditApplier {
    public static func apply(_ edits: [LSPTextEdit], to text: String) -> String? {
        guard !edits.isEmpty else { return text }

        // Precompute the UTF-16 start offset of each line so a (line, character) pair maps to a String
        // index in one pass. LSP characters are UTF-16 code units — the same unit Swift's `utf16` view
        // uses — so offsets line up exactly.
        let utf16 = Array(text.utf16)
        var lineStarts: [Int] = [0]
        for (index, unit) in utf16.enumerated() where unit == 0x0A { // '\n'
            lineStarts.append(index + 1)
        }

        func offset(of position: LSPPosition) -> Int? {
            guard position.line >= 0, position.line < lineStarts.count else {
                // A position on the line just past the last is valid only at character 0 (end of file).
                if position.line == lineStarts.count, position.character == 0 { return utf16.count }
                return nil
            }
            let lineStart = lineStarts[position.line]
            let lineEnd = position.line + 1 < lineStarts.count ? lineStarts[position.line + 1] : utf16.count
            let candidate = lineStart + max(0, position.character)
            guard candidate <= lineEnd else { return nil }
            return candidate
        }

        // Resolve every edit to a UTF-16 [start, end) range up front so a single bad edit aborts the
        // whole apply before we mutate anything.
        var resolved: [(start: Int, end: Int, text: String)] = []
        for edit in edits {
            guard let start = offset(of: edit.range.start),
                  let end = offset(of: edit.range.end),
                  start <= end, end <= utf16.count
            else { return nil }
            resolved.append((start, end, edit.newText))
        }
        // Apply from the back so an earlier splice never invalidates a later position. The LSP spec
        // forbids overlapping edits in one response, but the server is untrusted: reject any overlap
        // up front (return nil → keep the original file) rather than let `replaceSubrange` trap on a
        // range past the shrinking array. After sorting descending by start, "no overlap" means each
        // edit's end is at or before the previously-applied edit's start.
        resolved.sort { $0.start > $1.start }
        var previousStart = utf16.count
        for edit in resolved {
            guard edit.end <= previousStart else { return nil } // overlaps the edit applied before it
            previousStart = edit.start
        }

        var units = utf16
        for edit in resolved {
            let replacement = Array(edit.text.utf16)
            units.replaceSubrange(edit.start..<edit.end, with: replacement)
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}
