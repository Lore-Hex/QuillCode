import Foundation

extension HTMLToMarkdownConverter {
    mutating func handleOpenTagInsidePre(_ name: String, attributes: [String: String]) {
        if name == "br" {
            writer.writeText("\n")
        } else if name == "code", let context = preContext, context.language.isEmpty {
            preContext = PreContext(language: Self.codeLanguage(fromClass: attributes["class"]))
        }
    }

    mutating func startPre(attributes: [String: String]) {
        guard writer.pushCapture(byteLimit: Self.preByteLimit, preservesWhitespace: true) else {
            return
        }
        preContext = PreContext(language: Self.codeLanguage(fromClass: attributes["class"]))
    }

    mutating func finishPre() {
        guard let context = preContext, let content = writer.popCapture() else {
            preContext = nil
            return
        }
        preContext = nil
        var body = content
        while body.hasSuffix("\n") {
            body.removeLast()
        }
        while body.hasPrefix("\n") {
            body.removeFirst()
        }
        guard !body.isEmpty else {
            return
        }
        let fence = String(
            repeating: "`",
            count: min(max(3, longestBacktickRun(in: body) + 1), Self.maxCodeFenceLength)
        )
        writer.writeBlockLines([fence + context.language] + body.components(separatedBy: "\n") + [fence])
    }

    // MARK: - Tables

    mutating func handleTableOpen() {
        if table != nil {
            table?.nestedTables += 1
            return
        }
        table = TableContext()
    }

    mutating func handleTableClose() {
        guard var context = table else {
            return
        }
        if context.nestedTables > 0 {
            context.nestedTables -= 1
            table = context
            return
        }
        closeCellIfOpen()
        flushRowIfOpen()
        renderTable()
    }

    mutating func handleTableRowOpen() {
        guard table != nil, table?.nestedTables == 0 else {
            return
        }
        closeCellIfOpen()
        flushRowIfOpen()
        table?.currentRow = []
    }

    mutating func handleTableRowClose() {
        guard table != nil, table?.nestedTables == 0 else {
            return
        }
        closeCellIfOpen()
        flushRowIfOpen()
    }

    mutating func handleTableCellOpen() {
        guard var context = table, context.nestedTables == 0 else {
            return
        }
        closeCellIfOpen()
        if context.currentRow == nil {
            context.currentRow = []
        }
        context.cellOpen = writer.pushCapture(byteLimit: Self.tableCellByteLimit)
        table = context
    }

    mutating func handleTableCellClose() {
        closeCellIfOpen()
    }

    mutating func closeCellIfOpen() {
        guard var context = table, context.cellOpen else {
            return
        }
        context.cellOpen = false
        let text = writer.popCapture() ?? ""
        if var row = context.currentRow {
            if row.count < Self.maxTableColumns {
                row.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            context.currentRow = row
        }
        table = context
    }

    mutating func flushRowIfOpen() {
        guard var context = table, let row = context.currentRow else {
            return
        }
        context.currentRow = nil
        if !row.isEmpty, context.rows.count < Self.maxTableRows {
            context.rows.append(row)
        }
        table = context
    }

    mutating func handleTableCaptionOpen() {
        guard var context = table, context.nestedTables == 0, !context.captionOpen else {
            return
        }
        context.captionOpen = writer.pushCapture(byteLimit: Self.tableCellByteLimit)
        table = context
    }

    mutating func handleTableCaptionClose() {
        guard var context = table, context.captionOpen else {
            return
        }
        context.captionOpen = false
        context.caption = writer.popCapture()?.trimmingCharacters(in: .whitespacesAndNewlines)
        table = context
    }

    mutating func renderTable() {
        guard let context = table else {
            return
        }
        table = nil
        guard !context.rows.isEmpty else {
            writeCaptionIfNeeded(context.caption)
            return
        }
        let columnCount = min(context.rows.map(\.count).max() ?? 0, Self.maxTableColumns)
        guard columnCount > 0 else {
            return
        }
        writer.writeBlockLines(tableLines(for: context, columnCount: columnCount))
    }

    private func longestBacktickRun(in text: String) -> Int {
        var longestRun = 0
        var currentRun = 0
        for character in text {
            currentRun = character == "`" ? currentRun + 1 : 0
            longestRun = max(longestRun, currentRun)
        }
        return longestRun
    }

    private mutating func writeCaptionIfNeeded(_ caption: String?) {
        if let caption, !caption.isEmpty {
            writer.writeBlockLines(["*\(caption)*"])
        }
    }

    private func tableLines(for context: TableContext, columnCount: Int) -> [String] {
        var lines: [String] = []
        if let caption = context.caption, !caption.isEmpty {
            lines.append("*\(caption)*")
            lines.append("")
        }
        lines.append(renderTableRow(context.rows[0], columnCount: columnCount))
        lines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
        lines += context.rows.dropFirst().map {
            renderTableRow($0, columnCount: columnCount)
        }
        return lines
    }

    private func renderTableRow(_ row: [String], columnCount: Int) -> String {
        let padded = (0..<columnCount).map { index in
            index < row.count ? row[index].replacingOccurrences(of: "|", with: "\\|") : ""
        }
        return "| " + padded.joined(separator: " | ") + " |"
    }
}
