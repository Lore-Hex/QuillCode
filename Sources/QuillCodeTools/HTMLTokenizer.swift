import Foundation

enum HTMLToken: Equatable {
    case text(String)
    case openTag(name: String, attributes: [String: String], selfClosing: Bool)
    case closeTag(name: String)
}

/// A forgiving, single-pass HTML tokenizer over UTF-8 bytes. It never recurses and its cursor
/// advances on every call, so malformed input (unterminated comments, `<` soup, half-open
/// tags) can slow it down only linearly — it cannot hang, recurse deep, or throw. Tag names
/// and attribute counts are bounded; everything that is not a recognizable tag is text.
struct HTMLTokenizer {
    private let bytes: [UInt8]
    private var index = 0

    init(_ html: String) {
        self.bytes = Array(html.utf8)
    }

    mutating func next() -> HTMLToken? {
        guard index < bytes.count else {
            return nil
        }
        if bytes[index] == UInt8(ascii: "<") {
            if let token = parseMarkup() {
                return token
            }
            // A lone `<` that is not markup is literal text.
            index += 1
            return .text("<")
        }
        return .text(consumeText())
    }

    /// Consumes raw character data until the matching `</name` close tag — used for elements
    /// whose contents must never be tokenized as HTML (`script`, `style`, …). Returns the raw
    /// text; the close tag itself is also consumed. Missing close tag = rest of input.
    mutating func consumeRawText(until name: String) -> String {
        let closeMarker = Array("</\(name.lowercased())".utf8)
        var cursor = index
        while cursor < bytes.count {
            if bytes[cursor] == UInt8(ascii: "<"),
               matchesCaseInsensitive(closeMarker, at: cursor),
               isRawTextCloseTerminator(at: cursor + closeMarker.count) {
                let raw = decode(index..<cursor)
                index = cursor
                skipThroughTagEnd()
                return raw
            }
            cursor += 1
        }
        let raw = decode(index..<bytes.count)
        index = bytes.count
        return raw
    }

    // MARK: - Markup

    private mutating func parseMarkup() -> HTMLToken? {
        let start = index
        guard start + 1 < bytes.count else {
            return nil
        }
        let second = bytes[start + 1]
        if second == UInt8(ascii: "!") {
            skipDeclaration()
            return .text("")
        }
        if second == UInt8(ascii: "?") {
            index = start + 2
            skipUntilTagEnd(consumeTerminator: true)
            return .text("")
        }
        if second == UInt8(ascii: "/") {
            index = start + 2
            guard let name = consumeTagName() else {
                index = start
                return nil
            }
            skipUntilTagEnd(consumeTerminator: true)
            return .closeTag(name: name)
        }
        guard isASCIILetter(second) else {
            return nil
        }
        index = start + 1
        guard let name = consumeTagName() else {
            index = start
            return nil
        }
        let (attributes, selfClosing) = consumeAttributes()
        return .openTag(name: name, attributes: attributes, selfClosing: selfClosing)
    }

    private mutating func skipDeclaration() {
        // `<!-- comment -->`, `<![CDATA[ ... ]]>`, `<!DOCTYPE ...>` — all discarded.
        if matches("<!--", at: index) {
            index += 4
            skipPast("-->")
            return
        }
        if matches("<![CDATA[", at: index) {
            index += 9
            skipPast("]]>")
            return
        }
        index += 2
        skipUntilTagEnd(consumeTerminator: true)
    }

    private mutating func consumeTagName() -> String? {
        let start = index
        while index < bytes.count, isTagNameByte(bytes[index]), index - start < maxTagNameLength {
            index += 1
        }
        guard index > start else {
            return nil
        }
        return decode(start..<index).lowercased()
    }

    private mutating func consumeAttributes() -> ([String: String], Bool) {
        var attributes: [String: String] = [:]
        var selfClosing = false
        var count = 0
        while index < bytes.count {
            skipWhitespace()
            guard index < bytes.count else {
                break
            }
            let byte = bytes[index]
            if byte == UInt8(ascii: ">") {
                index += 1
                return (attributes, selfClosing)
            }
            if byte == UInt8(ascii: "/") {
                selfClosing = true
                index += 1
                continue
            }
            guard let name = consumeAttributeName() else {
                // Junk byte inside a tag — skip it so the cursor always advances.
                index += 1
                continue
            }
            skipWhitespace()
            var value = ""
            if index < bytes.count, bytes[index] == UInt8(ascii: "=") {
                index += 1
                skipWhitespace()
                value = consumeAttributeValue()
            }
            if count < maxAttributesPerTag {
                attributes[name] = HTMLEntityDecoder.decode(value)
                count += 1
            }
        }
        return (attributes, selfClosing)
    }

    private mutating func consumeAttributeName() -> String? {
        let start = index
        while index < bytes.count, isAttributeNameByte(bytes[index]), index - start < maxAttributeNameLength {
            index += 1
        }
        guard index > start else {
            return nil
        }
        return decode(start..<index).lowercased()
    }

    private mutating func consumeAttributeValue() -> String {
        guard index < bytes.count else {
            return ""
        }
        let quote = bytes[index]
        if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
            index += 1
            let start = index
            while index < bytes.count, bytes[index] != quote {
                index += 1
            }
            let value = decode(start..<min(index, start + maxAttributeValueLength))
            if index < bytes.count {
                index += 1
            }
            return value
        }
        let start = index
        while index < bytes.count, !isWhitespaceByte(bytes[index]), bytes[index] != UInt8(ascii: ">") {
            index += 1
        }
        return decode(start..<min(index, start + maxAttributeValueLength))
    }

    // MARK: - Text

    private mutating func consumeText() -> String {
        let start = index
        while index < bytes.count, bytes[index] != UInt8(ascii: "<") {
            index += 1
        }
        return HTMLEntityDecoder.decode(decode(start..<index))
    }

    // MARK: - Cursor helpers

    private mutating func skipWhitespace() {
        while index < bytes.count, isWhitespaceByte(bytes[index]) {
            index += 1
        }
    }

    private mutating func skipUntilTagEnd(consumeTerminator: Bool) {
        while index < bytes.count, bytes[index] != UInt8(ascii: ">") {
            index += 1
        }
        if consumeTerminator, index < bytes.count {
            index += 1
        }
    }

    private mutating func skipThroughTagEnd() {
        skipUntilTagEnd(consumeTerminator: true)
    }

    private mutating func skipPast(_ marker: String) {
        let markerBytes = Array(marker.utf8)
        var cursor = index
        while cursor < bytes.count {
            if bytes[cursor] == markerBytes[0], matches(marker, at: cursor) {
                index = cursor + markerBytes.count
                return
            }
            cursor += 1
        }
        index = bytes.count
    }

    private func matches(_ marker: String, at position: Int) -> Bool {
        let markerBytes = Array(marker.utf8)
        guard position + markerBytes.count <= bytes.count else {
            return false
        }
        for (offset, byte) in markerBytes.enumerated() where bytes[position + offset] != byte {
            return false
        }
        return true
    }

    private func matchesCaseInsensitive(_ marker: [UInt8], at position: Int) -> Bool {
        guard position + marker.count <= bytes.count else {
            return false
        }
        for (offset, byte) in marker.enumerated() where lowercased(bytes[position + offset]) != byte {
            return false
        }
        return true
    }

    /// After `</script` the next byte must end the tag name (whitespace, `>`, `/`, or EOF) —
    /// otherwise `</scripty` inside a script would end raw-text mode early.
    private func isRawTextCloseTerminator(at position: Int) -> Bool {
        guard position < bytes.count else {
            return true
        }
        let byte = bytes[position]
        return isWhitespaceByte(byte) || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "/")
    }

    private func decode(_ range: Range<Int>) -> String {
        guard range.lowerBound < range.upperBound else {
            return ""
        }
        return String(decoding: bytes[range], as: UTF8.self)
    }

    private func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
    }

    private func isASCIILetter(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    private func isTagNameByte(_ byte: UInt8) -> Bool {
        isASCIILetter(byte)
            || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ":")
    }

    private func isAttributeNameByte(_ byte: UInt8) -> Bool {
        !isWhitespaceByte(byte)
            && byte != UInt8(ascii: "=") && byte != UInt8(ascii: ">")
            && byte != UInt8(ascii: "/") && byte != UInt8(ascii: "\"")
            && byte != UInt8(ascii: "'") && byte != UInt8(ascii: "<")
    }

    private func isWhitespaceByte(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
            || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
            || byte == 0x0C
    }

    private let maxTagNameLength = 64
    private let maxAttributesPerTag = 32
    private let maxAttributeNameLength = 128
    private let maxAttributeValueLength = 8192
}
