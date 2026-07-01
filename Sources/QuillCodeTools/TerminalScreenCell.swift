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
