enum TerminalScreenCellWidth {
    static func width(
        of character: Character,
        ambiguousPolicy: TerminalOutputAmbiguousWidthPolicy = .narrow
    ) -> Int {
        let scalars = Array(character.unicodeScalars)
        guard !scalars.isEmpty else { return 0 }
        if scalars.allSatisfy(isZeroWidthScalar) { return 0 }
        if isEmojiPresentationSequence(scalars) { return 2 }
        if scalars.contains(where: isWideScalar) { return 2 }
        if scalars.contains(where: isAmbiguousWidthScalar) { return ambiguousPolicy.cellWidth }
        return 1
    }

    private static func isZeroWidthScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark:
            return true
        default:
            break
        }
        return scalar.value == 0x200D
            || (0xFE00...0xFE0F).contains(scalar.value)
            || (0xE0100...0xE01EF).contains(scalar.value)
    }

    private static func isEmojiPresentationSequence(_ scalars: [Unicode.Scalar]) -> Bool {
        guard scalars.contains(where: { $0.value == 0xFE0F }) else { return false }
        return scalars.contains { scalar in
            !isZeroWidthScalar(scalar) && scalar.properties.isEmoji
        }
    }

    private static func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x1100...0x115F).contains(value)
            || (0x2329...0x232A).contains(value)
            || (0x2E80...0xA4CF).contains(value)
            || (0xAC00...0xD7A3).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0xFE10...0xFE19).contains(value)
            || (0xFE30...0xFE6F).contains(value)
            || (0xFF00...0xFF60).contains(value)
            || (0xFFE0...0xFFE6).contains(value)
            || (0x1F300...0x1FAFF).contains(value)
    }

    private static func isAmbiguousWidthScalar(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return value == 0x00A1
            || value == 0x00A4
            || value == 0x00A7
            || value == 0x00A8
            || value == 0x00AA
            || value == 0x00AD
            || value == 0x00AE
            || (0x00B0...0x00B4).contains(value)
            || (0x00B6...0x00BA).contains(value)
            || (0x00BC...0x00BF).contains(value)
            || value == 0x00C6
            || value == 0x00D0
            || value == 0x00D7
            || value == 0x00D8
            || (0x00DE...0x00E1).contains(value)
            || value == 0x00E6
            || (0x00E8...0x00EA).contains(value)
            || (0x00EC...0x00ED).contains(value)
            || value == 0x00F0
            || (0x00F2...0x00F3).contains(value)
            || (0x00F7...0x00FA).contains(value)
            || value == 0x00FC
            || value == 0x00FE
            || (0x0391...0x03A1).contains(value)
            || (0x03A3...0x03A9).contains(value)
            || (0x03B1...0x03C1).contains(value)
            || (0x03C3...0x03C9).contains(value)
            || value == 0x0401
            || (0x0410...0x044F).contains(value)
            || value == 0x0451
            || value == 0x2010
            || (0x2013...0x2016).contains(value)
            || (0x2018...0x2019).contains(value)
            || (0x201C...0x201D).contains(value)
            || (0x2020...0x2022).contains(value)
            || (0x2024...0x2027).contains(value)
            || value == 0x2030
            || (0x2032...0x2033).contains(value)
            || value == 0x2035
            || value == 0x203B
            || value == 0x203E
            || value == 0x20AC
            || value == 0x2126
            || value == 0x212B
            || (0x2153...0x2154).contains(value)
            || (0x215B...0x215E).contains(value)
            || (0x2160...0x216B).contains(value)
            || (0x2170...0x2179).contains(value)
            || (0x2190...0x2199).contains(value)
            || (0x2200...0x22FF).contains(value)
            || value == 0x2312
            || (0x2460...0x24E9).contains(value)
            || (0x24EB...0x254B).contains(value)
            || (0x2550...0x2573).contains(value)
            || (0x2580...0x258F).contains(value)
            || (0x2592...0x2595).contains(value)
            || (0x25A0...0x25A1).contains(value)
            || (0x25A3...0x25A9).contains(value)
            || (0x25B2...0x25B3).contains(value)
            || (0x25B6...0x25B7).contains(value)
            || (0x25BC...0x25BD).contains(value)
            || (0x25C0...0x25C1).contains(value)
            || (0x25C6...0x25C8).contains(value)
            || value == 0x25CB
            || (0x25CE...0x25D1).contains(value)
            || (0x25E2...0x25E5).contains(value)
            || value == 0x25EF
            || (0x2605...0x2606).contains(value)
            || value == 0x2609
            || (0x260E...0x260F).contains(value)
            || (0x2614...0x2615).contains(value)
            || value == 0x261C
            || value == 0x261E
            || value == 0x2640
            || value == 0x2642
            || (0x2660...0x2661).contains(value)
            || (0x2663...0x2665).contains(value)
            || (0x2667...0x266A).contains(value)
            || (0x266C...0x266D).contains(value)
            || value == 0x266F
            || value == 0x273D
            || (0x2776...0x277F).contains(value)
            || value == 0x2B56
            || (0x3248...0x324F).contains(value)
            || (0xE000...0xF8FF).contains(value)
            || value == 0xFFFD
    }
}
