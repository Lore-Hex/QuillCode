import Foundation

enum ToolArtifactTablePreviewBuilder {
    static func tablePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactTablePreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              let delimiter = delimiter(for: fileURL)
        else { return nil }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            guard let data = try handle.read(upToCount: byteLimit + 1),
                  !data.isEmpty,
                  !data.prefix(byteLimit).contains(0)
            else { return nil }

            let wasByteTruncated = data.count > byteLimit
            guard var text = String(data: Data(data.prefix(byteLimit)), encoding: .utf8) else {
                return nil
            }
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")

            let parsedRows = parseRows(text, delimiter: delimiter.character)
                .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
            guard !parsedRows.isEmpty else { return nil }

            let totalParsedRowCount = parsedRows.count
            let previewRows = Array(parsedRows.prefix(rowLimit + 1))
            let wasRowTruncated = previewRows.count > rowLimit || totalParsedRowCount > rowLimit
            let limitedRows = Array(previewRows.prefix(rowLimit))
            guard let headerRow = limitedRows.first else { return nil }

            let columnCount = min(maxColumnCount(in: limitedRows), columnLimit)
            let headers = normalizedHeaderRow(headerRow, columnCount: columnCount)
            let bodyRows = limitedRows.dropFirst().map { normalizedRow($0, columnCount: columnCount) }

            return ToolArtifactTablePreview(
                delimiterLabel: delimiter.label,
                rowCountLabel: rowCountLabel(parsed: totalParsedRowCount, byteTruncated: wasByteTruncated),
                columnCount: columnCount,
                headers: headers,
                rows: bodyRows,
                isTruncated: wasByteTruncated || wasRowTruncated || maxColumnCount(in: parsedRows) > columnLimit
            )
        } catch {
            return nil
        }
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else { return nil }
        return url
    }

    private static func delimiter(for fileURL: URL) -> Delimiter? {
        switch fileURL.pathExtension.lowercased() {
        case "csv":
            return Delimiter(character: ",", label: "CSV")
        case "tsv":
            return Delimiter(character: "\t", label: "TSV")
        default:
            return nil
        }
    }

    private static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var index = text.startIndex
        var isQuoted = false

        while index < text.endIndex {
            let character = text[index]
            if isQuoted {
                if character == "\"" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                        field.append("\"")
                        index = nextIndex
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                isQuoted = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                if rows.count > rowLimit + 1 {
                    break
                }
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func normalizedHeaderRow(_ row: [String], columnCount: Int) -> [String] {
        normalizedRow(row, columnCount: columnCount).enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Column \(index + 1)" : trimmed
        }
    }

    private static func normalizedRow(_ row: [String], columnCount: Int) -> [String] {
        (0..<columnCount).map { index in
            guard index < row.count else { return "" }
            let trimmed = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(cellCharacterLimit))
        }
    }

    private static func maxColumnCount(in rows: [[String]]) -> Int {
        rows.map(\.count).max() ?? 0
    }

    private static func rowCountLabel(parsed: Int, byteTruncated: Bool) -> String {
        if byteTruncated {
            return "\(parsed)+ rows"
        }
        return "\(parsed) row\(parsed == 1 ? "" : "s")"
    }

    private struct Delimiter {
        var character: Character
        var label: String
    }

    private static let byteLimit = 64 * 1024
    private static let rowLimit = 8
    private static let columnLimit = 6
    private static let cellCharacterLimit = 80
}
