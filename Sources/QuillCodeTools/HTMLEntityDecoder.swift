import Foundation

/// Decodes HTML character references (`&amp;`, `&#233;`, `&#x1F600;`) in text and attribute
/// values. Built for hostile input: numeric references are length- and range-clamped (an
/// out-of-range or surrogate code point becomes U+FFFD, never a trap), and anything that does
/// not parse is passed through literally.
enum HTMLEntityDecoder {
    static func decode(_ text: String) -> String {
        guard text.contains("&") else {
            return text
        }
        var result = ""
        result.reserveCapacity(text.count)
        var remainder = Substring(text)
        while let ampersand = remainder.firstIndex(of: "&") {
            result += remainder[..<ampersand]
            remainder = remainder[ampersand...]
            if let (scalar, afterEntity) = parseEntity(remainder) {
                result += scalar
                remainder = afterEntity
            } else {
                result.append("&")
                remainder = remainder.dropFirst()
            }
        }
        result += remainder
        return result
    }

    /// Parses one entity at the start of `text` (which begins with `&`). Returns the decoded
    /// string and the remainder after the entity, or nil when this is not a valid entity.
    private static func parseEntity(_ text: Substring) -> (String, Substring)? {
        let body = text.dropFirst()
        guard let semicolon = body.prefix(maxEntityLength).firstIndex(of: ";") else {
            return nil
        }
        let name = body[..<semicolon]
        let afterEntity = body[body.index(after: semicolon)...]
        guard !name.isEmpty else {
            return nil
        }
        if name.hasPrefix("#") {
            guard let scalar = numericScalar(name.dropFirst()) else {
                return nil
            }
            return (String(scalar), afterEntity)
        }
        guard let replacement = namedEntities[String(name)] else {
            return nil
        }
        return (replacement, afterEntity)
    }

    private static func numericScalar(_ digits: Substring) -> Unicode.Scalar? {
        var value: UInt32 = 0
        let isHex = digits.hasPrefix("x") || digits.hasPrefix("X")
        let number = isHex ? digits.dropFirst() : digits
        guard !number.isEmpty, number.count <= 8 else {
            return nil
        }
        for character in number {
            guard let digit = character.hexDigitValue, isHex || digit < 10 else {
                return nil
            }
            value = value * (isHex ? 16 : 10) + UInt32(digit)
            if value > 0x10FFFF {
                return replacementScalar
            }
        }
        guard value != 0, let scalar = Unicode.Scalar(value) else {
            // NUL, surrogates (D800–DFFF), and out-of-range values all land here — the
            // failable initializer is the clamp, so hostile references cannot trap.
            return replacementScalar
        }
        return scalar
    }

    private static let replacementScalar = Unicode.Scalar(0xFFFD)!

    private static let maxEntityLength = 40

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "copy": "©", "reg": "®", "trade": "™", "sect": "§", "para": "¶", "middot": "·",
        "bull": "•", "hellip": "…", "prime": "′", "Prime": "″",
        "mdash": "—", "ndash": "–", "shy": "",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "sbquo": "\u{201A}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "times": "×", "divide": "÷", "plusmn": "±", "minus": "−", "ne": "≠",
        "le": "≤", "ge": "≥", "asymp": "≈", "equiv": "≡", "infin": "∞", "sum": "∑",
        "deg": "°", "micro": "µ", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "sup1": "¹", "sup2": "²", "sup3": "³",
        "cent": "¢", "pound": "£", "yen": "¥", "euro": "€", "curren": "¤",
        "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔",
        "dagger": "†", "Dagger": "‡", "permil": "‰",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "lambda": "λ", "mu": "μ", "pi": "π", "sigma": "σ", "omega": "ω",
        "Delta": "Δ", "Omega": "Ω", "Sigma": "Σ", "Pi": "Π",
        "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å",
        "ccedil": "ç", "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë",
        "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï",
        "ntilde": "ñ", "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö",
        "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü",
        "Agrave": "À", "Aacute": "Á", "Auml": "Ä", "Eacute": "É", "Ouml": "Ö", "Uuml": "Ü",
        "szlig": "ß", "yuml": "ÿ", "oelig": "œ", "OElig": "Œ", "aelig": "æ", "AElig": "Æ",
        "oslash": "ø", "Oslash": "Ø"
    ]
}
