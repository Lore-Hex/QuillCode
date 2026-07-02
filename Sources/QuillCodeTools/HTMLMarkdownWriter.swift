import Foundation

/// Output side of the HTML→markdown converter: a budgeted text sink with pending-separator
/// tracking (so blocks are separated by exactly one blank line), blockquote line prefixes,
/// and a bounded stack of capture buffers for constructs that need their content before they
/// can be emitted (link text, inline code, table cells, `<pre>` bodies).
///
/// Every write path is bounded: the main buffer stops growing past `maxOutputBytes` (setting
/// `truncated`), and each capture has its own byte limit past which input is dropped.
final class HTMLMarkdownWriter {
    private(set) var truncated = false

    /// Blockquote nesting; each level prefixes lines with "> ". Capped by the converter.
    var quoteDepth = 0

    private let maxOutputBytes: Int
    private var output = ""
    private var outputBytes = 0
    private var pendingSeparator = Separator.none
    private var pendingSpace = false
    private var atBoundary = true
    private var captures: [Capture] = []

    private enum Separator: Int, Comparable {
        case none = 0
        case line = 1
        case block = 2

        static func < (lhs: Separator, rhs: Separator) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct Capture {
        var buffer = ""
        var bytes = 0
        var byteLimit: Int
        var preservesWhitespace: Bool
        var pendingSpace = false
        var atBoundary = true
    }

    init(maxOutputBytes: Int) {
        self.maxOutputBytes = max(1024, maxOutputBytes)
    }

    var captureDepth: Int {
        captures.count
    }

    // MARK: - Separators

    func requestLineBreak() {
        guard captures.isEmpty else {
            setCapturePendingSpace()
            return
        }
        pendingSeparator = max(pendingSeparator, .line)
    }

    func requestBlockBreak() {
        guard captures.isEmpty else {
            setCapturePendingSpace()
            return
        }
        pendingSeparator = max(pendingSeparator, .block)
    }

    // MARK: - Inline writing

    /// Writes text with whitespace runs collapsed to single spaces and control characters
    /// stripped. Inside a whitespace-preserving capture the text is kept verbatim (minus
    /// dangerous control characters).
    func writeText(_ text: String) {
        if let index = captures.indices.last, captures[index].preservesWhitespace {
            appendToCapture(sanitizedPreservingWhitespace(text), at: index)
            return
        }
        writeCollapsed(text)
    }

    /// Writes literal markdown syntax (emphasis markers, rendered links). `flushingSpace`
    /// controls whether a pending inter-word space lands before the marker (openers) or stays
    /// pending until the following text (closers, so `x </b>y` becomes `x**` + ` y`).
    func writeMarker(_ marker: String, flushingSpace: Bool) {
        guard !marker.isEmpty else {
            return
        }
        if let index = captures.indices.last {
            if flushingSpace, captures[index].pendingSpace, !captures[index].atBoundary {
                appendToCapture(" ", at: index)
            }
            captures[index].pendingSpace = flushingSpace ? false : captures[index].pendingSpace
            appendToCapture(marker, at: index)
            captures[index].atBoundary = false
            return
        }
        flushSeparator()
        if flushingSpace, pendingSpace, !atBoundary {
            appendRaw(" ")
        }
        if flushingSpace {
            pendingSpace = false
        }
        appendRaw(marker)
        atBoundary = false
    }

    // MARK: - Block writing

    /// Emits whole lines (fenced code, tables, horizontal rules) with the quote prefix applied
    /// to each line, separated from surrounding content by a blank line on each side.
    func writeBlockLines(_ lines: [String]) {
        guard !lines.isEmpty else {
            return
        }
        if let index = captures.indices.last {
            // Block content inside a capture (a table in a link, …) flattens to spaced text.
            let flattened = lines.joined(separator: " ")
            if captures[index].pendingSpace, !captures[index].atBoundary {
                appendToCapture(" ", at: index)
            }
            captures[index].pendingSpace = false
            appendToCapture(flattened, at: index)
            captures[index].atBoundary = false
            return
        }
        pendingSeparator = max(pendingSeparator, .block)
        flushSeparator()
        let prefix = linePrefix()
        appendRaw(lines.map { prefix + $0 }.joined(separator: "\n"))
        pendingSeparator = .block
        pendingSpace = false
        atBoundary = true
    }

    // MARK: - Captures

    /// Starts routing writes into a new capture buffer. Returns false (and captures nothing)
    /// when the capture stack is at its bound — callers then simply let content flow through.
    func pushCapture(byteLimit: Int, preservesWhitespace: Bool = false) -> Bool {
        guard captures.count < Self.maxCaptureDepth else {
            return false
        }
        captures.append(Capture(byteLimit: max(0, byteLimit), preservesWhitespace: preservesWhitespace))
        return true
    }

    func popCapture() -> String? {
        guard let capture = captures.popLast() else {
            return nil
        }
        return capture.buffer
    }

    // MARK: - Finish

    func finalizedMarkdown() -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

    private func writeCollapsed(_ text: String) {
        let hasVisibleContent = text.unicodeScalars.contains {
            !isCollapsibleWhitespace($0) && !isStrippedControl($0)
        }
        guard hasVisibleContent else {
            if text.unicodeScalars.contains(where: isCollapsibleWhitespace) {
                if let index = captures.indices.last {
                    captures[index].pendingSpace = true
                } else {
                    pendingSpace = true
                }
            }
            return
        }
        if let index = captures.indices.last {
            var localPendingSpace = captures[index].pendingSpace
            var localAtBoundary = captures[index].atBoundary
            let piece = collapsedPiece(text, pendingSpace: &localPendingSpace, atBoundary: &localAtBoundary)
            captures[index].pendingSpace = localPendingSpace
            captures[index].atBoundary = localAtBoundary
            appendToCapture(piece, at: index)
        } else {
            flushSeparator()
            var localPendingSpace = pendingSpace
            var localAtBoundary = atBoundary
            let piece = collapsedPiece(text, pendingSpace: &localPendingSpace, atBoundary: &localAtBoundary)
            pendingSpace = localPendingSpace
            atBoundary = localAtBoundary
            appendRaw(piece)
        }
    }

    private func collapsedPiece(
        _ text: String,
        pendingSpace: inout Bool,
        atBoundary: inout Bool
    ) -> String {
        var piece = ""
        piece.reserveCapacity(min(text.utf8.count, 4096))
        for scalar in text.unicodeScalars {
            if isCollapsibleWhitespace(scalar) {
                pendingSpace = true
                continue
            }
            if isStrippedControl(scalar) {
                continue
            }
            if pendingSpace, !atBoundary {
                piece.unicodeScalars.append(" ")
            }
            pendingSpace = false
            piece.unicodeScalars.append(scalar)
            atBoundary = false
        }
        return piece
    }

    private func flushSeparator() {
        guard pendingSeparator != .none else {
            return
        }
        let separator = pendingSeparator
        pendingSeparator = .none
        let prefix = linePrefix()
        guard !output.isEmpty else {
            // At the very start of the document there is nothing to separate FROM, but a
            // blockquote prefix still has to open the first line.
            appendRaw(prefix)
            atBoundary = true
            return
        }
        switch separator {
        case .none:
            break
        case .line:
            appendRaw("\n" + prefix)
        case .block:
            let blankLine = prefix.trimmingCharacters(in: .whitespaces)
            appendRaw("\n" + blankLine + "\n" + prefix)
        }
        pendingSpace = false
        atBoundary = true
    }

    private func linePrefix() -> String {
        String(repeating: "> ", count: max(0, quoteDepth))
    }

    private func appendRaw(_ text: String) {
        guard !truncated, !text.isEmpty else {
            return
        }
        let bytes = text.utf8.count
        if outputBytes + bytes <= maxOutputBytes {
            output += text
            outputBytes += bytes
            return
        }
        // Partial fit: a single oversized piece (one giant text node) must not be dropped
        // wholesale — keep whole scalars until the budget runs out, then stop.
        let remaining = maxOutputBytes - outputBytes
        if remaining > 0 {
            var kept = ""
            var keptBytes = 0
            for scalar in text.unicodeScalars {
                let scalarBytes = String(scalar).utf8.count
                guard keptBytes + scalarBytes <= remaining else {
                    break
                }
                kept.unicodeScalars.append(scalar)
                keptBytes += scalarBytes
            }
            output += kept
            outputBytes += keptBytes
        }
        truncated = true
    }

    private func appendToCapture(_ text: String, at index: Int) {
        guard !text.isEmpty else {
            return
        }
        let remaining = captures[index].byteLimit - captures[index].bytes
        guard remaining > 0 else {
            return
        }
        let bytes = text.utf8.count
        if bytes <= remaining {
            captures[index].buffer += text
            captures[index].bytes += bytes
            return
        }
        // Partial fit: keep whole scalars until the capture's byte budget runs out.
        var kept = ""
        var keptBytes = 0
        for scalar in text.unicodeScalars {
            let scalarBytes = String(scalar).utf8.count
            guard keptBytes + scalarBytes <= remaining else {
                break
            }
            kept.unicodeScalars.append(scalar)
            keptBytes += scalarBytes
        }
        captures[index].buffer += kept
        captures[index].bytes += keptBytes
    }

    private func setCapturePendingSpace() {
        guard let index = captures.indices.last else {
            return
        }
        if captures[index].preservesWhitespace {
            appendToCapture("\n", at: index)
        } else {
            captures[index].pendingSpace = true
        }
    }

    private func sanitizedPreservingWhitespace(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !isStrippedControl(scalar)
        }.map(Character.init))
    }

    private func isCollapsibleWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{0C}"
    }

    private func isStrippedControl(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value < 0x20 && scalar != "\n" && scalar != "\t") || scalar.value == 0x7F
    }

    private static let maxCaptureDepth = 8
}
