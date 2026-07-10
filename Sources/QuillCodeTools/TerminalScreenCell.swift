struct TerminalScreenCell: Equatable {
    var text: String
    var isContinuation: Bool
    var style: TerminalTextStyle

    static let blank = TerminalScreenCell(text: " ", isContinuation: false, style: .plain)

    static func blank(style: TerminalTextStyle) -> TerminalScreenCell {
        TerminalScreenCell(text: " ", isContinuation: false, style: style)
    }

    static func continuation(style: TerminalTextStyle) -> TerminalScreenCell {
        TerminalScreenCell(text: "", isContinuation: true, style: style)
    }

    static func content(_ character: Character, style: TerminalTextStyle = .plain) -> TerminalScreenCell {
        TerminalScreenCell(text: String(character), isContinuation: false, style: style)
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

enum TerminalScreenStyledText {
    static func render(_ lines: [[TerminalScreenCell]]) -> TerminalRenderedFrame {
        var runs: [TerminalTextRun] = []
        for (lineIndex, line) in lines.enumerated() {
            for cell in line where !cell.isContinuation {
                append(cell.text, style: cell.style, to: &runs)
            }
            if lineIndex < lines.count - 1 {
                append("\n", style: .plain, to: &runs)
            }
        }
        return TerminalRenderedFrame(
            text: runs.map(\.text).joined(),
            runs: runs
        )
    }

    private static func append(
        _ text: String,
        style: TerminalTextStyle,
        to runs: inout [TerminalTextRun]
    ) {
        guard !text.isEmpty else { return }
        if runs.last?.style == style {
            runs[runs.count - 1].text += text
        } else {
            runs.append(TerminalTextRun(text: text, style: style))
        }
    }
}
