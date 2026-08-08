import Foundation

/// Mechanically reconciles ID-backed aggregate tables and bullets with CSV/TSV records read during
/// a source-only run. Requiring explicit record IDs keeps illustrative prose from being treated as
/// exhaustive analysis.
enum AgentTabularSourceGroundingGate {
    struct SourceTable {
        let path: String
        let headers: [String]
        let recordsByID: [String: [String: String]]

        var sortedIDs: [String] { recordsByID.keys.sorted() }
    }

    static func correction(
        userMessage: String,
        issuesByPath: [String: [String]],
        auditCounts: [String: Int]
    ) -> AgentArtifactTextQualityGate.Correction? {
        guard AgentSourceGroundingGate.requestsSourceOnlyGrounding(in: userMessage) else {
            return nil
        }
        let required = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        guard let entry = issuesByPath.sorted(by: { $0.key < $1.key }).first(where: { path, issues in
            !issues.isEmpty
                && auditCounts[path, default: 0] < 2
                && required.contains(where: {
                    AgentArtifactVerificationGate.pathsMatch($0, path)
                })
        }) else { return nil }

        let details = entry.value.prefix(12).map { "- \($0)" }.joined(separator: "\n")
        return .init(
            path: entry.key,
            prompt: """
            The current ./\(entry.key) does not reconcile with tabular source records read in this \
            run:
            \(details)

            Recompute the affected slices from the source file, preferably with the shell for \
            arithmetic. Correct every affected table row or aggregate bullet and every prose \
            conclusion derived from those claims. Fill any named source-dimension section that is \
            empty. Preserve the source record IDs so the result remains auditable.

            Return exactly one tool action now: rewrite ./\(entry.key) with the corrected complete \
            content. Do not return a final answer yet.
            """
        )
    }

    static func issues(
        content: String,
        path: String,
        sourceReadsByPath: [String: String]
    ) -> [String] {
        guard ["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        else { return [] }

        let sources = sourceReadsByPath.compactMap { sourcePath, rendered in
            parseSourceTable(path: sourcePath, renderedText: rendered)
        }
        guard !sources.isEmpty else { return [] }

        var found: [String] = []
        for source in sources {
            for markdownTable in parseMarkdownTables(content) {
                found.append(contentsOf: issues(in: markdownTable, source: source))
            }
            found.append(contentsOf: proseIssues(in: content, source: source))
            found.append(contentsOf: emptyDimensionSectionIssues(in: content, source: source))
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }

    static func parseSourceTable(path: String, renderedText: String) -> SourceTable? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard ext == "csv" || ext == "tsv" else { return nil }
        guard !renderedText.contains("[showing lines"),
              !renderedText.contains("[line truncated]")
        else { return nil }
        let text = removingReadLineNumbers(renderedText)
        let rows = parseDelimited(text, delimiter: ext == "tsv" ? "\t" : ",")
        guard let rawHeaders = rows.first, rawHeaders.count >= 2 else { return nil }
        let headers = rawHeaders.map(canonicalHeader)
        guard let idIndex = headers.firstIndex(where: isIDHeader) else { return nil }

        var records: [String: [String: String]] = [:]
        for values in rows.dropFirst() {
            guard idIndex < values.count else { continue }
            let id = values[idIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            var record: [String: String] = [:]
            for (index, header) in headers.enumerated() where !header.isEmpty {
                record[header] = index < values.count
                    ? values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            }
            records[id] = record
        }
        guard !records.isEmpty else { return nil }
        return SourceTable(path: path, headers: headers, recordsByID: records)
    }

    private struct MarkdownTable {
        let headers: [String]
        let rows: [[String]]
    }

    private static func proseIssues(in content: String, source: SourceTable) -> [String] {
        let knownIDs = Dictionary(uniqueKeysWithValues: source.recordsByID.keys.map {
            ($0.lowercased(), $0)
        })
        var activeField: String?
        var found: [String] = []

        for rawLine in content.components(separatedBy: .newlines) {
            if let heading = firstCapture(headingRegex, in: rawLine) {
                activeField = sourceHeader(forSectionHeading: heading, in: source.headers)
                continue
            }
            guard let field = activeField,
                  let prose = firstCapture(bulletRegex, in: rawLine),
                  let rawLabel = prose.split(separator: ":", maxSplits: 1).first.map(String.init)
            else { continue }

            let knownValues = Set(source.recordsByID.values.map {
                canonicalValue($0[field] ?? "")
            })
            guard let value = categoryValue(in: rawLabel, knownValues: knownValues) else { continue }
            let ids = extractedIDs(from: [prose], knownIDs: knownIDs)
            guard !ids.isEmpty else { continue }

            let mismatches = ids.filter { id in
                canonicalValue(source.recordsByID[id]?[field] ?? "") != value
            }
            if !mismatches.isEmpty {
                let actual = mismatches.map { id in
                    "\(id)=\(source.recordsByID[id]?[field] ?? "blank")"
                }.joined(separator: ", ")
                found.append(
                    "Bullet '\(cleanMarkdown(rawLabel))' labels \(field)=\(displayValue(value)), "
                        + "but the source says \(actual)."
                )
            }

            let matching = source.sortedIDs.filter { id in
                canonicalValue(source.recordsByID[id]?[field] ?? "") == value
            }
            if Set(matching) != Set(ids) {
                found.append(
                    "Bullet '\(cleanMarkdown(rawLabel))' lists [\(ids.joined(separator: ", "))], "
                        + "but source rows matching \(field)=\(displayValue(value)) are "
                        + "[\(matching.joined(separator: ", "))]."
                )
            }
            found.append(contentsOf: proseCountIssues(
                prose: prose,
                label: cleanMarkdown(rawLabel),
                ids: ids,
                source: source
            ))
        }
        return found
    }

    private static func emptyDimensionSectionIssues(
        in content: String,
        source: SourceTable
    ) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var found: [String] = []
        for (index, line) in lines.enumerated() {
            guard let heading = firstCapture(headingRegex, in: line),
                  let field = sourceHeader(forSectionHeading: heading, in: source.headers)
            else { continue }
            let body = lines.dropFirst(index + 1).prefix { candidate in
                firstCapture(headingRegex, in: candidate) == nil
            }
            if body.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                found.append(
                    "Section '\(cleanMarkdown(heading))' is empty despite source column \(field)."
                )
            }
        }
        return found
    }

    private static func proseCountIssues(
        prose: String,
        label: String,
        ids: [String],
        source: SourceTable
    ) -> [String] {
        let range = NSRange(prose.startIndex..., in: prose)
        var found: [String] = []
        for match in recordCountRegex.matches(in: prose, range: range) {
            guard let declared = integerCapture(match, at: 1, in: prose), declared != ids.count
            else { continue }
            found.append(
                "Bullet '\(label)' declares \(declared) records, but its listed source IDs "
                    + "support \(ids.count) (\(ids.joined(separator: ", ")))."
            )
        }
        for regex in [outcomePairRegex, outcomeWordPairRegex] {
            for match in regex.matches(in: prose, range: range) {
                guard let declaredWon = integerCapture(match, at: 1, in: prose),
                      let declaredLost = integerCapture(match, at: 2, in: prose)
                else { continue }
                let expectedWon = expectedCount(kind: .won, ids: ids, source: source)
                let expectedLost = expectedCount(kind: .lost, ids: ids, source: source)
                if declaredWon != expectedWon || declaredLost != expectedLost {
                    found.append(
                        "Bullet '\(label)' declares \(declaredWon)W/\(declaredLost)L, but its "
                            + "listed source IDs support \(expectedWon)W/\(expectedLost)L."
                    )
                }
            }
        }
        return found
    }

    private static func categoryValue(in rawLabel: String, knownValues: Set<String>) -> String? {
        let label = canonicalValue(rawLabel)
        if knownValues.contains(label) { return label }
        return knownValues.sorted { $0.count > $1.count }.first { value in
            label.hasPrefix(value + " ")
        }
    }

    private static func issues(in table: MarkdownTable, source: SourceTable) -> [String] {
        let knownIDs = Dictionary(uniqueKeysWithValues: source.recordsByID.keys.map {
            ($0.lowercased(), $0)
        })
        let canonicalHeaders = table.headers.map(canonicalHeader)
        let countColumns = canonicalHeaders.enumerated().compactMap { index, header in
            countKind(for: header).map { (index, $0) }
        }
        guard !countColumns.isEmpty else { return [] }
        let hasExampleIDs = canonicalHeaders.contains(where: {
            $0.contains("example") || $0.contains("sample") || $0.contains("selected")
        })

        var found: [String] = []
        for row in table.rows {
            let ids = extractedIDs(from: row, knownIDs: knownIDs)
            guard !ids.isEmpty else { continue }
            let rowLabel = row.first.map(cleanMarkdown) ?? ids.joined(separator: ", ")
            let constraints = sourceConstraints(
                row: row,
                markdownHeaders: canonicalHeaders,
                source: source
            )

            for (field, expectedValue) in constraints {
                let mismatches = ids.filter { id in
                    guard let actual = source.recordsByID[id]?[field] else { return false }
                    return canonicalValue(actual) != expectedValue
                }
                if !mismatches.isEmpty {
                    let actual = mismatches.compactMap { id -> String? in
                        source.recordsByID[id]?[field].map { "\(id)=\($0.isEmpty ? "blank" : $0)" }
                    }.joined(separator: ", ")
                    found.append(
                        "Row '\(rowLabel)' labels \(field)=\(displayValue(expectedValue)), but "
                            + "the source says \(actual)."
                    )
                }
            }

            for (index, kind) in countColumns where index < row.count {
                guard let declared = integerCell(row[index]) else { continue }
                let expected = expectedCount(kind: kind, ids: ids, source: source)
                if declared != expected {
                    found.append(
                        "Row '\(rowLabel)' declares \(cleanMarkdown(table.headers[index]))="
                            + "\(declared), but its listed source IDs support \(expected) "
                            + "(\(ids.joined(separator: ", ")))."
                    )
                }
            }

            guard !hasExampleIDs, !constraints.isEmpty else { continue }
            let outcomeFilter = inferredOutcomeFilter(from: countColumns.map(\.1))
            let matching = source.sortedIDs.filter { id in
                guard let record = source.recordsByID[id] else { return false }
                let dimensionsMatch = constraints.allSatisfy { field, value in
                    canonicalValue(record[field] ?? "") == value
                }
                guard dimensionsMatch else { return false }
                guard let outcomeFilter else { return true }
                return canonicalValue(outcomeValue(in: record)) == outcomeFilter
            }
            if Set(matching) != Set(ids) {
                let dimensions = constraints.sorted(by: { $0.key < $1.key }).map {
                    "\($0.key)=\(displayValue($0.value))"
                }.joined(separator: ", ")
                found.append(
                    "Row '\(rowLabel)' lists [\(ids.joined(separator: ", "))], but source rows "
                        + "matching \(dimensions)\(outcomeFilter.map { ", outcome=\($0)" } ?? "") "
                        + "are [\(matching.joined(separator: ", "))]."
                )
            }
        }
        return found
    }

    private enum CountKind {
        case total
        case won
        case lost
    }

    private static func countKind(for header: String) -> CountKind? {
        if header == "won" || header == "win" || header == "wins" || header.hasSuffix("wins") {
            return .won
        }
        if header == "lost" || header == "loss" || header == "losses" || header.hasSuffix("losses") {
            return .lost
        }
        if ["total", "count", "records", "record", "occurrences", "opportunities"].contains(header) {
            return .total
        }
        return nil
    }

    private static func inferredOutcomeFilter(from kinds: [CountKind]) -> String? {
        let unique = Set(kinds.map { kind in
            switch kind {
            case .total: "total"
            case .won: "won"
            case .lost: "lost"
            }
        })
        if unique == ["won"] { return "won" }
        if unique == ["lost"] { return "lost" }
        return nil
    }

    private static func expectedCount(
        kind: CountKind,
        ids: [String],
        source: SourceTable
    ) -> Int {
        switch kind {
        case .total:
            return ids.count
        case .won:
            return ids.filter { id in
                source.recordsByID[id].map { canonicalValue(outcomeValue(in: $0)) == "won" } ?? false
            }.count
        case .lost:
            return ids.filter { id in
                source.recordsByID[id].map { canonicalValue(outcomeValue(in: $0)) == "lost" } ?? false
            }.count
        }
    }

    private static func outcomeValue(in record: [String: String]) -> String {
        for key in ["outcome", "status", "result"] {
            if let value = record[key] { return value }
        }
        return ""
    }

    private static func sourceConstraints(
        row: [String],
        markdownHeaders: [String],
        source: SourceTable
    ) -> [String: String] {
        var constraints: [String: String] = [:]
        for (index, markdownHeader) in markdownHeaders.enumerated() where index < row.count {
            let sourceHeader = sourceHeader(for: markdownHeader, in: source.headers)
            guard let sourceHeader, !isIDHeader(sourceHeader) else { continue }
            let value = canonicalValue(row[index])
            let knownValues = Set(source.recordsByID.values.map {
                canonicalValue($0[sourceHeader] ?? "")
            })
            if knownValues.contains(value) {
                constraints[sourceHeader] = value
            }
        }

        if let dimensionIndex = markdownHeaders.firstIndex(of: "dimension"),
           let valueIndex = markdownHeaders.firstIndex(of: "value"),
           dimensionIndex < row.count,
           valueIndex < row.count,
           let field = sourceHeader(for: canonicalHeader(row[dimensionIndex]), in: source.headers) {
            let value = canonicalValue(row[valueIndex])
            let knownValues = Set(source.recordsByID.values.map { canonicalValue($0[field] ?? "") })
            if knownValues.contains(value) { constraints[field] = value }
        }
        return constraints
    }

    private static func sourceHeader(for markdownHeader: String, in sourceHeaders: [String]) -> String? {
        if sourceHeaders.contains(markdownHeader) { return markdownHeader }
        let aliases = [
            "leadsource": "source",
            "dealsource": "source",
            "founderaction": "founderaction",
            "primaryobjection": "objection",
        ]
        if let alias = aliases[markdownHeader], sourceHeaders.contains(alias) { return alias }
        return nil
    }

    private static func sourceHeader(
        forSectionHeading heading: String,
        in sourceHeaders: [String]
    ) -> String? {
        let canonical = canonicalHeader(heading)
        if let direct = sourceHeader(for: canonical, in: sourceHeaders) { return direct }
        return sourceHeaders.filter { header in
            !isIDHeader(header) && header.count >= 4
        }.sorted { $0.count > $1.count }.first { header in
            canonical.hasPrefix(header + "pattern")
                || canonical.hasSuffix("by" + header)
                || canonical.hasSuffix(header + "analysis")
        }
    }

    private static func extractedIDs(
        from row: [String],
        knownIDs: [String: String]
    ) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        for cell in row {
            let tokens = cell.split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }
            for token in tokens {
                if let id = knownIDs[String(token).lowercased()], seen.insert(id).inserted {
                    found.append(id)
                }
            }
        }
        return found.sorted()
    }

    private static func integerCell(_ cell: String) -> Int? {
        let cleaned = cleanMarkdown(cell)
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        guard let match = integerPrefixRegex.firstMatch(in: cleaned, range: range),
              let valueRange = Range(match.range(at: 1), in: cleaned)
        else { return nil }
        return Int(cleaned[valueRange])
    }

    private static func firstCapture(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }

    private static func integerCapture(
        _ match: NSTextCheckingResult,
        at index: Int,
        in text: String
    ) -> Int? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    private static func parseMarkdownTables(_ content: String) -> [MarkdownTable] {
        let lines = content.components(separatedBy: .newlines)
        var tables: [MarkdownTable] = []
        var index = 0
        while index + 1 < lines.count {
            let headers = markdownCells(lines[index])
            let separator = markdownCells(lines[index + 1])
            guard !headers.isEmpty,
                  headers.count == separator.count,
                  separator.allSatisfy(isMarkdownSeparator)
            else {
                index += 1
                continue
            }
            var rows: [[String]] = []
            index += 2
            while index < lines.count {
                let cells = markdownCells(lines[index])
                guard cells.count == headers.count else { break }
                rows.append(cells)
                index += 1
            }
            tables.append(MarkdownTable(headers: headers, rows: rows))
        }
        return tables
    }

    private static func markdownCells(_ line: String) -> [String] {
        guard line.contains("|") else { return [] }
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func isMarkdownSeparator(_ cell: String) -> Bool {
        let value = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
    }

    private static func removingReadLineNumbers(_ rendered: String) -> String {
        let lines = rendered.components(separatedBy: .newlines)
        let hasReadPrefixes = lines.first(where: { !$0.isEmpty }).map { line in
            guard let tab = line.firstIndex(of: "\t") else { return false }
            return Int(line[..<tab].trimmingCharacters(in: .whitespaces)) != nil
        } ?? false
        guard hasReadPrefixes else { return rendered }
        return lines.compactMap { line in
            guard let tab = line.firstIndex(of: "\t"),
                  Int(line[..<tab].trimmingCharacters(in: .whitespaces)) != nil
            else { return nil }
            return String(line[line.index(after: tab)...])
        }.joined(separator: "\n")
    }

    private static func parseDelimited(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == delimiter, !quoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !quoted {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" { index = next }
                }
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    private static func canonicalHeader(_ value: String) -> String {
        cleanMarkdown(value).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func canonicalValue(_ value: String) -> String {
        var cleaned = cleanMarkdown(value).lowercased()
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*\([^)]*\)\s*$"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ["", "-", "n/a", "na", "none", "no competitor"].contains(cleaned) { return "none" }
        return cleaned
    }

    private static func cleanMarkdown(_ value: String) -> String {
        value.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayValue(_ canonical: String) -> String {
        canonical == "none" ? "none" : canonical
    }

    private static func isIDHeader(_ header: String) -> Bool {
        header == "id" || header == "ids" || header.hasSuffix("id") || header.hasSuffix("ids")
    }

    private static let integerPrefixRegex = try! NSRegularExpression(pattern: #"^\s*(\d+)\b"#)
    private static let headingRegex = try! NSRegularExpression(
        pattern: #"^\s{0,3}#{1,6}\s+(.+?)\s*$"#
    )
    private static let bulletRegex = try! NSRegularExpression(pattern: #"^\s*[-*+]\s+(.+)$"#)
    private static let recordCountRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(\d+)\s+records?\b"#
    )
    private static let outcomePairRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(\d+)\s*w\s*/\s*(\d+)\s*l\b"#
    )
    private static let outcomeWordPairRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(\d+)\s+won\b[^\r\n]{0,20}?\b(\d+)\s+lost\b"#
    )
}
