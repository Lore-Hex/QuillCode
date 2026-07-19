import Foundation

enum ToolArtifactXUnitPreviewBuilder {
    static func xunitPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactXUnitPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "xml",
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize > 0, fileSize <= byteLimit else { return nil }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard !data.contains(0) else { return nil }
            let collector = XUnitPreviewCollector()
            let parser = XMLParser(data: data)
            parser.delegate = collector
            parser.shouldProcessNamespaces = false
            parser.shouldReportNamespacePrefixes = true
            guard parser.parse(),
                  let preview = collector.preview(fileSize: fileSize)
            else {
                return nil
            }
            return preview.hasDisplayContent ? preview : nil
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
        else {
            return nil
        }
        return url
    }

    private static let byteLimit = 512 * 1_024
}

private final class XUnitPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var assemblyCount = 0
    private var collectionCount = 0
    private var testCount = 0
    private var passedCount = 0
    private var failedCount = 0
    private var skippedCount = 0
    private var durationSeconds = 0.0
    private var hasAggregateCounts = false
    private var hasDuration = false
    private var assemblyLabels: [String] = []
    private var failureLabels: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let label = localElementName(elementName: elementName, qName: qName)
        if depth == 0 {
            rootElementLabel = label
        }

        switch label {
        case "assembly":
            recordAssembly(attributeDict)
        case "collection":
            collectionCount += 1
        case "test":
            recordTest(attributeDict)
        default:
            break
        }
        depth += 1
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        depth = max(0, depth - 1)
    }

    func preview(fileSize: Int) -> ToolArtifactXUnitPreview? {
        guard rootElementLabel == "assemblies" || rootElementLabel == "assembly",
              assemblyCount > 0 || testCount > 0
        else {
            return nil
        }
        return ToolArtifactXUnitPreview(
            assemblyCount: assemblyCount,
            collectionCount: collectionCount,
            testCount: testCount,
            passedCount: passedCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            durationLabel: hasDuration ? durationLabel(for: durationSeconds) : nil,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            assemblyPreviewLabels: previewLabels(for: assemblyLabels),
            failurePreviewLabels: previewLabels(for: failureLabels)
        )
    }

    private func recordAssembly(_ attributes: [String: String]) {
        assemblyCount += 1
        if let name = sanitizedLabel(attributes["name"]) {
            assemblyLabels.append(lastPathComponent(name))
        }
        guard let total = intAttribute("total", in: attributes) else { return }
        hasAggregateCounts = true
        testCount += total
        passedCount += intAttribute("passed", in: attributes) ?? 0
        failedCount += intAttribute("failed", in: attributes) ?? 0
        skippedCount += intAttribute("skipped", in: attributes) ?? 0
        if let time = doubleAttribute("time", in: attributes) {
            hasDuration = true
            durationSeconds += time
        }
    }

    private func recordTest(_ attributes: [String: String]) {
        let result = sanitizedLabel(attributes["result"])?.lowercased()
        if !hasAggregateCounts {
            testCount += 1
            switch result {
            case "pass", "passed":
                passedCount += 1
            case "fail", "failed":
                failedCount += 1
            case "skip", "skipped":
                skippedCount += 1
            default:
                break
            }
        }
        if !hasAggregateCounts,
           let time = doubleAttribute("time", in: attributes) {
            hasDuration = true
            durationSeconds += time
        }
        if result == "fail" || result == "failed",
           let label = testLabel(from: attributes),
           !failureLabels.contains(label) {
            failureLabels.append(label)
        }
    }

    private func testLabel(from attributes: [String: String]) -> String? {
        sanitizedLabel(attributes["name"])
            ?? sanitizedLabel(attributes["method"])
            ?? sanitizedLabel(attributes["type"])
    }

    private func lastPathComponent(_ value: String) -> String {
        value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? value
    }

    private func intAttribute(_ key: String, in attributes: [String: String]) -> Int? {
        guard let value = attributes[key].flatMap(sanitizedLabel),
              let intValue = Int(value),
              intValue >= 0
        else {
            return nil
        }
        return intValue
    }

    private func doubleAttribute(_ key: String, in attributes: [String: String]) -> Double? {
        guard let value = attributes[key].flatMap(sanitizedLabel),
              let doubleValue = Double(value),
              doubleValue >= 0
        else {
            return nil
        }
        return doubleValue
    }

    private func durationLabel(for seconds: Double) -> String {
        if seconds < 1 {
            return "\(Int((seconds * 1_000).rounded())) ms"
        }
        let rounded = (seconds * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) s"
        }
        return "\(rounded) s"
    }

    private func previewLabels(for labels: [String]) -> [String] {
        Array(labels.prefix(previewLabelLimit))
    }

    private func sanitizedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let collapsedWhitespace = label
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedWhitespace.isEmpty else { return nil }
        return String(collapsedWhitespace.prefix(characterLimit))
    }

    private func localElementName(elementName: String, qName: String?) -> String {
        let qualified = qName.flatMap { $0.isEmpty ? nil : $0 } ?? elementName
        return qualified.split(separator: ":").last.map(String.init) ?? qualified
    }

    private let previewLabelLimit = 6
    private let characterLimit = 96
}
