import Foundation

enum ToolArtifactRobotXMLPreviewBuilder {
    static func robotXMLPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactRobotXMLPreview? {
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
            let collector = RobotXMLPreviewCollector()
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

private final class RobotXMLPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var generatedLabel: String?
    private var generatorLabel: String?
    private var suiteCount = 0
    private var testCount = 0
    private var keywordCount = 0
    private var passedCount = 0
    private var failedCount = 0
    private var skippedCount = 0
    private var durationSeconds = 0.0
    private var hasDuration = false
    private var elementStack: [String] = []
    private var activeTestName: String?
    private var suiteLabels: [String] = []
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
            generatedLabel = sanitizedLabel(attributeDict["generated"])
            generatorLabel = sanitizedLabel(attributeDict["generator"])
        }

        switch label {
        case "suite":
            recordSuite(attributeDict)
        case "test":
            recordTest(attributeDict)
        case "kw":
            keywordCount += 1
        case "status":
            recordStatus(attributeDict)
        default:
            break
        }

        elementStack.append(label)
        depth += 1
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let label = localElementName(elementName: elementName, qName: qName)
        if label == "test" {
            activeTestName = nil
        }
        if !elementStack.isEmpty {
            _ = elementStack.removeLast()
        }
        depth = max(0, depth - 1)
    }

    func preview(fileSize: Int) -> ToolArtifactRobotXMLPreview? {
        guard rootElementLabel == "robot",
              suiteCount > 0 || testCount > 0
        else {
            return nil
        }
        return ToolArtifactRobotXMLPreview(
            generatedLabel: generatedLabel,
            generatorLabel: generatorLabel,
            suiteCount: suiteCount,
            testCount: testCount,
            keywordCount: keywordCount,
            passedCount: passedCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            durationLabel: hasDuration ? durationLabel(for: durationSeconds) : nil,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            suitePreviewLabels: previewLabels(for: suiteLabels),
            failurePreviewLabels: previewLabels(for: failureLabels)
        )
    }

    private func recordSuite(_ attributes: [String: String]) {
        suiteCount += 1
        if let name = sanitizedLabel(attributes["name"]), !suiteLabels.contains(name) {
            suiteLabels.append(name)
        }
    }

    private func recordTest(_ attributes: [String: String]) {
        testCount += 1
        activeTestName = sanitizedLabel(attributes["name"]) ?? sanitizedLabel(attributes["id"])
    }

    private func recordStatus(_ attributes: [String: String]) {
        guard elementStack.last == "test" else { return }
        let status = sanitizedLabel(attributes["status"])?.lowercased()
        switch status {
        case "pass", "passed":
            passedCount += 1
        case "fail", "failed", "error":
            failedCount += 1
            if let label = activeTestName, !failureLabels.contains(label) {
                failureLabels.append(label)
            }
        case "skip", "skipped":
            skippedCount += 1
        default:
            break
        }
        if let seconds = doubleAttribute("elapsed", in: attributes) {
            hasDuration = true
            durationSeconds += seconds
        } else if let milliseconds = doubleAttribute("elapsedtime", in: attributes) {
            hasDuration = true
            durationSeconds += milliseconds / 1_000
        }
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
