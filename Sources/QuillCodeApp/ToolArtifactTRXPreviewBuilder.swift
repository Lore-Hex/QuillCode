import Foundation

enum ToolArtifactTRXPreviewBuilder {
    static func trxPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactTRXPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "trx",
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
            let collector = TRXPreviewCollector()
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

private final class TRXPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var testRunName: String?
    private var totalCount = 0
    private var passedCount = 0
    private var failedCount = 0
    private var inconclusiveCount = 0
    private var notExecutedCount = 0
    private var durationSeconds = 0.0
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
            testRunName = sanitizedLabel(attributeDict["name"])
        }

        if label == "UnitTestResult" {
            recordResult(attributeDict)
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

    func preview(fileSize: Int) -> ToolArtifactTRXPreview? {
        guard rootElementLabel == "TestRun",
              totalCount > 0
        else {
            return nil
        }
        return ToolArtifactTRXPreview(
            testRunName: testRunName,
            totalCount: totalCount,
            passedCount: passedCount,
            failedCount: failedCount,
            inconclusiveCount: inconclusiveCount,
            notExecutedCount: notExecutedCount,
            durationLabel: hasDuration ? durationLabel(for: durationSeconds) : nil,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            failurePreviewLabels: previewLabels(for: failureLabels)
        )
    }

    private func recordResult(_ attributes: [String: String]) {
        totalCount += 1
        let outcome = sanitizedLabel(attributes["outcome"])?.lowercased()
        switch outcome {
        case "passed":
            passedCount += 1
        case "failed", "error", "timeout", "aborted":
            failedCount += 1
            if let label = resultLabel(from: attributes),
               !failureLabels.contains(label) {
                failureLabels.append(label)
            }
        case "inconclusive":
            inconclusiveCount += 1
        case "notexecuted", "not executed", "skipped":
            notExecutedCount += 1
        default:
            break
        }
        if let duration = durationSeconds(attributes["duration"]) {
            hasDuration = true
            durationSeconds += duration
        }
    }

    private func resultLabel(from attributes: [String: String]) -> String? {
        sanitizedLabel(attributes["testName"])
            ?? sanitizedLabel(attributes["testId"])
            ?? sanitizedLabel(attributes["executionId"])
    }

    private func durationSeconds(_ value: String?) -> Double? {
        guard let value = sanitizedLabel(value) else { return nil }
        let components = value.split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]),
              hours >= 0,
              minutes >= 0,
              seconds >= 0
        else {
            return nil
        }
        return (hours * 3_600) + (minutes * 60) + seconds
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
