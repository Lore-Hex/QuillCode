struct TerminalScreenCell: Equatable {
    var text: String
    var isContinuation: Bool

    static let blank = TerminalScreenCell(text: " ", isContinuation: false)
    static let continuation = TerminalScreenCell(text: "", isContinuation: true)

    static func content(_ character: Character) -> TerminalScreenCell {
        TerminalScreenCell(text: String(character), isContinuation: false)
    }

    var isBlank: Bool {
        !isContinuation && text == " "
    }
}

enum TerminalScreenCellWidth {
    static func width(of character: Character) -> Int {
        let scalars = Array(character.unicodeScalars)
        guard !scalars.isEmpty else { return 0 }
        if scalars.allSatisfy(isZeroWidthScalar) { return 0 }
        return scalars.contains(where: isWideScalar) ? 2 : 1
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
}

enum TerminalScreenLineText {
    static func render(_ line: [TerminalScreenCell]) -> String {
        var output = ""
        output.reserveCapacity(renderedCharacterCount(in: line))
        for cell in line where !cell.isContinuation {
            output.append(contentsOf: cell.text)
        }
        return output
    }

    private static func renderedCharacterCount(in line: [TerminalScreenCell]) -> Int {
        line.reduce(0) { total, cell in
            cell.isContinuation ? total : total + cell.text.count
        }
    }
}
