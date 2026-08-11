import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(PDFKit)
import PDFKit
#endif

enum RichDocumentTextExtractor {
    private static let maximumArchiveOutputBytes = 8 * 1_024 * 1_024

    static func extract(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return extractPDF(from: url)
        case "docx":
            return extractOfficeXML(
                from: url,
                matching: { $0 == "word/document.xml" },
                sectionName: { _ in "Document" }
            )
        case "pptx":
            return extractOfficeXML(
                from: url,
                matching: { $0.range(of: #"^ppt/slides/slide\d+\.xml$"#, options: .regularExpression) != nil },
                sectionName: { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            )
        case "xlsx":
            return extractWorkbook(from: url)
        default:
            return nil
        }
    }

    private static func extractPDF(from url: URL) -> String? {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        let sections = (0..<document.pageCount).compactMap { index -> String? in
            guard let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            return "## Page \(index + 1)\n\(text)"
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
        #else
        return nil
        #endif
    }

    private static func extractOfficeXML(
        from url: URL,
        matching predicate: (String) -> Bool,
        sectionName: (String) -> String
    ) -> String? {
        guard let entries = archiveEntries(in: url) else { return nil }
        let sections = entries.filter(predicate).sorted(by: naturalArchiveOrder).compactMap { entry -> String? in
            guard let data = archiveEntry(entry, in: url),
                  let text = OfficeXMLTextCollector.text(from: data),
                  !text.isEmpty
            else { return nil }
            return "## \(sectionName(entry))\n\(text)"
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private static func extractWorkbook(from url: URL) -> String? {
        guard let entries = archiveEntries(in: url) else { return nil }
        let sharedStrings = entries.contains("xl/sharedStrings.xml")
            ? archiveEntry("xl/sharedStrings.xml", in: url).map(SpreadsheetSharedStringCollector.strings(from:)) ?? []
            : []
        let sheetNames = entries.contains("xl/workbook.xml")
            ? archiveEntry("xl/workbook.xml", in: url).map(SpreadsheetWorkbookCollector.sheetNames(from:)) ?? []
            : []
        let sheets = entries
            .filter { $0.range(of: #"^xl/worksheets/sheet\d+\.xml$"#, options: .regularExpression) != nil }
            .sorted(by: naturalArchiveOrder)
            .enumerated()
            .compactMap { index, entry -> String? in
                guard let data = archiveEntry(entry, in: url) else { return nil }
                let text = SpreadsheetSheetCollector.text(from: data, sharedStrings: sharedStrings)
                guard !text.isEmpty else { return nil }
                let name = sheetNames.indices.contains(index)
                    ? sheetNames[index]
                    : URL(fileURLWithPath: entry).deletingPathExtension().lastPathComponent
                return "## \(name)\n\(text)"
            }
        return sheets.isEmpty ? nil : sheets.joined(separator: "\n\n")
    }

    private static func archiveEntries(in url: URL) -> [String]? {
        guard let data = runUnzip(arguments: ["-Z1", url.path]),
              let output = String(data: data, encoding: .utf8)
        else { return nil }
        return output.split(whereSeparator: \Character.isNewline).map(String.init)
    }

    private static func archiveEntry(_ entry: String, in url: URL) -> Data? {
        runUnzip(arguments: ["-p", url.path, entry])
    }

    private static func naturalArchiveOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func runUnzip(arguments: [String]) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            var data = Data()
            while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                data.append(chunk)
                if data.count > maximumArchiveOutputBytes {
                    process.terminate()
                    process.waitUntilExit()
                    return nil
                }
            }
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            if process.isRunning { process.terminate() }
            return nil
        }
    }
}

private final class OfficeXMLTextCollector: NSObject, XMLParserDelegate {
    private var fragments: [String] = []
    private var currentText = ""
    private var isReadingText = false

    static func text(from data: Data) -> String? {
        let collector = OfficeXMLTextCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        guard parser.parse() else { return nil }
        return collector.fragments.joined(separator: "\n")
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "t" {
            isReadingText = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingText { currentText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "t" else { return }
        isReadingText = false
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { fragments.append(value) }
    }
}

private final class SpreadsheetWorkbookCollector: NSObject, XMLParserDelegate {
    private var sheetNames: [String] = []

    static func sheetNames(from data: Data) -> [String] {
        let collector = SpreadsheetWorkbookCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        return parser.parse() ? collector.sheetNames : []
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "sheet", let name = attributeDict["name"], !name.isEmpty {
            sheetNames.append(name)
        }
    }
}

private final class SpreadsheetSharedStringCollector: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var isInItem = false
    private var isInText = false

    static func strings(from data: Data) -> [String] {
        let collector = SpreadsheetSharedStringCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        return parser.parse() ? collector.strings : []
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "si" {
            isInItem = true
            current = ""
        } else if isInItem, elementName == "t" {
            isInText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInText { current += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "t" {
            isInText = false
        } else if elementName == "si" {
            strings.append(current)
            isInItem = false
        }
    }
}

private final class SpreadsheetSheetCollector: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [String] = []
    private var cells: [String] = []
    private var cellReference = ""
    private var cellType = ""
    private var cellValue = ""
    private var cellFormula = ""
    private var isReadingValue = false
    private var isReadingFormula = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func text(from data: Data, sharedStrings: [String]) -> String {
        let collector = SpreadsheetSheetCollector(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        return parser.parse() ? collector.rows.joined(separator: "\n") : ""
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "row" {
            cells = []
        } else if elementName == "c" {
            cellReference = attributeDict["r"] ?? "cell"
            cellType = attributeDict["t"] ?? ""
            cellValue = ""
            cellFormula = ""
        } else if elementName == "f" {
            isReadingFormula = true
        } else if elementName == "v" || elementName == "t" {
            isReadingValue = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingFormula {
            cellFormula += string
        } else if isReadingValue {
            cellValue += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "f" {
            isReadingFormula = false
        } else if elementName == "v" || elementName == "t" {
            isReadingValue = false
        } else if elementName == "c" {
            let value: String
            if cellType == "s", let index = Int(cellValue), sharedStrings.indices.contains(index) {
                value = sharedStrings[index]
            } else {
                value = cellValue
            }
            if cellFormula.isEmpty {
                cells.append("\(cellReference)=\(value)")
            } else if value.isEmpty {
                cells.append("\(cellReference)=[formula=\(cellFormula)]")
            } else {
                cells.append("\(cellReference)=\(value) [formula=\(cellFormula)]")
            }
        } else if elementName == "row", !cells.isEmpty {
            rows.append(cells.joined(separator: "\t"))
        }
    }
}
