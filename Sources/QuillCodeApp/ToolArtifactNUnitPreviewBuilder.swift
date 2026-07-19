import Foundation

enum ToolArtifactNUnitPreviewBuilder {
    static func nunitPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactNUnitPreview? {
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
            let collector = NUnitPreviewCollector()
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

private final class NUnitPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var runName: String?
    private var testCount = 0
    private var passedCount = 0
    private var failedCount = 0
    private var inconclusiveCount = 0
    private var skippedCount = 0
    private var durationSeconds = 0.0
    private var hasAggregateCounts = false
    private var hasDuration = false
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
            runName = sanitizedLabel(attributeDict["name"])
            recordRun(attributeDict)
        }

        if label == "test-case" {
            recordTestCase(attributeDict)
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

    func preview(fileSize: Int) -> ToolArtifactNUnitPreview? {
        guard rootElementLabel == "test-run",
              testCount > 0
        else {
            return nil
        }
        return ToolArtifactNUnitPreview(
            runName: runName,
            testCount: testCount,
            passedCount: passedCount,
            failedCount: failedCount,
            inconclusiveCount: inconclusiveCount,
            skippedCount: skippedCount,
            durationLabel: hasDuration ? durationLabel(for: durationSeconds) : nil,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            failurePreviewLabels: previewLabels(for: failureLabels)
        )
    }

    private func recordRun(_ attributes: [String: String]) {
        guard let total = intAttribute("total", in: attributes) else { return }
        hasAggregateCounts = true
        testCount = total
        passedCount = intAttribute("passed", in: attributes) ?? 0
        failedCount = intAttribute("failed", in: attributes) ?? 0
        inconclusiveCount = intAttribute("inconclusive", in: attributes) ?? 0
        skippedCount = intAttribute("skipped", in: attributes) ?? 0
        if let duration = doubleAttribute("duration", in: attributes) {
            hasDuration = true
            durationSeconds = duration
        }
    }

    private func recordTestCase(_ attributes: [String: String]) {
        let result = sanitizedLabel(attributes["result"])?.lowercased()
        if !hasAggregateCounts {
            testCount += 1
            switch result {
            case "passed":
                passedCount += 1
            case "failed", "error", "cancelled":
                failedCount += 1
            case "inconclusive":
                inconclusiveCount += 1
            case "skipped", "ignored":
                skippedCount += 1
            default:
                break
            }
        }
        if !hasAggregateCounts,
           let duration = doubleAttribute("duration", in: attributes) {
            hasDuration = true
            durationSeconds += duration
        }
        if result == "failed" || result == "error" || result == "cancelled",
           let label = testLabel(from: attributes),
           !failureLabels.contains(label) {
            failureLabels.append(label)
        }
    }

    private func testLabel(from attributes: [String: String]) -> String? {
        sanitizedLabel(attributes["fullname"])
            ?? sanitizedLabel(attributes["name"])
            ?? sanitizedLabel(attributes["id"])
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
