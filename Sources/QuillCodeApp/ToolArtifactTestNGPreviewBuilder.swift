import Foundation

enum ToolArtifactTestNGPreviewBuilder {
    static func testNGPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactTestNGPreview? {
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
            let collector = TestNGPreviewCollector()
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

private final class TestNGPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var suiteCount = 0
    private var testGroupCount = 0
    private var classCount = 0
    private var methodCount = 0
    private var passedCount = 0
    private var failedCount = 0
    private var skippedCount = 0
    private var suiteDurationMilliseconds = 0.0
    private var methodDurationMilliseconds = 0.0
    private var hasSuiteDuration = false
    private var hasMethodDuration = false
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
        }

        switch label {
        case "suite":
            recordSuite(attributeDict)
        case "test":
            testGroupCount += 1
        case "class":
            classCount += 1
        case "test-method":
            recordTestMethod(attributeDict)
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

    func preview(fileSize: Int) -> ToolArtifactTestNGPreview? {
        guard rootElementLabel == "testng-results",
              suiteCount > 0 || methodCount > 0
        else {
            return nil
        }
        return ToolArtifactTestNGPreview(
            suiteCount: suiteCount,
            testGroupCount: testGroupCount,
            classCount: classCount,
            methodCount: methodCount,
            passedCount: passedCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            durationLabel: resolvedDurationMilliseconds.map(durationLabel),
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
        if let duration = doubleAttribute("duration-ms", in: attributes) {
            hasSuiteDuration = true
            suiteDurationMilliseconds += duration
        }
    }

    private func recordTestMethod(_ attributes: [String: String]) {
        guard boolAttribute("is-config", in: attributes) != true else { return }
        methodCount += 1
        let status = sanitizedLabel(attributes["status"])?.lowercased()
        switch status {
        case "pass", "passed":
            passedCount += 1
        case "fail", "failed":
            failedCount += 1
            if let label = testMethodLabel(from: attributes), !failureLabels.contains(label) {
                failureLabels.append(label)
            }
        case "skip", "skipped":
            skippedCount += 1
        default:
            break
        }
        if let duration = doubleAttribute("duration-ms", in: attributes) {
            hasMethodDuration = true
            methodDurationMilliseconds += duration
        }
    }

    private var resolvedDurationMilliseconds: Double? {
        if hasSuiteDuration {
            return suiteDurationMilliseconds
        }
        if hasMethodDuration {
            return methodDurationMilliseconds
        }
        return nil
    }

    private func testMethodLabel(from attributes: [String: String]) -> String? {
        sanitizedLabel(attributes["signature"])
            ?? sanitizedLabel(attributes["name"])
            ?? sanitizedLabel(attributes["description"])
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

    private func boolAttribute(_ key: String, in attributes: [String: String]) -> Bool? {
        guard let value = attributes[key].flatMap(sanitizedLabel)?.lowercased() else { return nil }
        if value == "true" || value == "1" {
            return true
        }
        if value == "false" || value == "0" {
            return false
        }
        return nil
    }

    private func durationLabel(for milliseconds: Double) -> String {
        if milliseconds < 1_000 {
            return "\(Int(milliseconds.rounded())) ms"
        }
        let seconds = (milliseconds / 10).rounded() / 100
        if seconds == seconds.rounded() {
            return "\(Int(seconds)) s"
        }
        return "\(seconds) s"
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
