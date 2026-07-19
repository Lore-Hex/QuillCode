import Foundation

enum ToolArtifactJUnitPreviewBuilder {
    static func junitPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactJUnitPreview? {
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
            let collector = JUnitPreviewCollector()
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

private final class JUnitPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var suiteLabels: [String] = []
    private var suiteCount = 0
    private var aggregateTestCount = 0
    private var aggregateFailureCount = 0
    private var aggregateErrorCount = 0
    private var aggregateSkippedCount = 0
    private var aggregateDurationSeconds = 0.0
    private var hasAggregateTestCounts = false
    private var hasAggregateFailureCounts = false
    private var hasAggregateErrorCounts = false
    private var hasAggregateSkippedCounts = false
    private var hasAggregateDuration = false
    private var testcaseCount = 0
    private var observedFailureCount = 0
    private var observedErrorCount = 0
    private var observedSkippedCount = 0
    private var activeTestcaseLabel: String?
    private var activeTestcaseHasFailure = false
    private var activeTestcaseHasError = false
    private var activeTestcaseHasSkipped = false
    private var failureLabels: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let label = qualifiedElementName(elementName: elementName, qName: qName)
        if depth == 0 {
            rootElementLabel = label
        }

        switch label {
        case "testsuite":
            recordSuite(attributeDict)
        case "testcase":
            recordTestcase(attributeDict)
        case "failure":
            activeTestcaseHasFailure = true
        case "error":
            activeTestcaseHasError = true
        case "skipped":
            activeTestcaseHasSkipped = true
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
        let label = qualifiedElementName(elementName: elementName, qName: qName)
        if label == "testcase" {
            finishTestcase()
        }
        depth = max(0, depth - 1)
    }

    func preview(fileSize: Int) -> ToolArtifactJUnitPreview? {
        guard rootElementLabel == "testsuites" || rootElementLabel == "testsuite" else { return nil }
        let tests = hasAggregateTestCounts ? aggregateTestCount : testcaseCount
        let failures = hasAggregateFailureCounts ? aggregateFailureCount : observedFailureCount
        let errors = hasAggregateErrorCounts ? aggregateErrorCount : observedErrorCount
        let skipped = hasAggregateSkippedCounts ? aggregateSkippedCount : observedSkippedCount
        return ToolArtifactJUnitPreview(
            suiteCount: suiteCount,
            testCount: tests,
            failureCount: failures,
            errorCount: errors,
            skippedCount: skipped,
            durationLabel: hasAggregateDuration ? durationLabel(for: aggregateDurationSeconds) : nil,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            suitePreviewLabels: previewLabels(for: suiteLabels),
            failurePreviewLabels: previewLabels(for: failureLabels)
        )
    }

    private func recordSuite(_ attributes: [String: String]) {
        suiteCount += 1
        if let name = sanitizedLabel(attributes["name"]) {
            suiteLabels.append(name)
        }
        if let tests = intAttribute("tests", in: attributes) {
            hasAggregateTestCounts = true
            aggregateTestCount += tests
        }
        if let failures = intAttribute("failures", in: attributes) {
            hasAggregateFailureCounts = true
            aggregateFailureCount += failures
        }
        if let errors = intAttribute("errors", in: attributes) {
            hasAggregateErrorCounts = true
            aggregateErrorCount += errors
        }
        if let skipped = intAttribute("skipped", in: attributes) {
            hasAggregateSkippedCounts = true
            aggregateSkippedCount += skipped
        }
        if let time = doubleAttribute("time", in: attributes) {
            hasAggregateDuration = true
            aggregateDurationSeconds += time
        }
    }

    private func recordTestcase(_ attributes: [String: String]) {
        testcaseCount += 1
        activeTestcaseLabel = testcaseLabel(className: attributes["classname"], name: attributes["name"])
        activeTestcaseHasFailure = false
        activeTestcaseHasError = false
        activeTestcaseHasSkipped = false
    }

    private func finishTestcase() {
        if activeTestcaseHasFailure {
            observedFailureCount += 1
            appendFailureLabel()
        }
        if activeTestcaseHasError {
            observedErrorCount += 1
            appendFailureLabel()
        }
        if activeTestcaseHasSkipped {
            observedSkippedCount += 1
        }
        activeTestcaseLabel = nil
        activeTestcaseHasFailure = false
        activeTestcaseHasError = false
        activeTestcaseHasSkipped = false
    }

    private func appendFailureLabel() {
        guard let activeTestcaseLabel,
              !failureLabels.contains(activeTestcaseLabel)
        else {
            return
        }
        failureLabels.append(activeTestcaseLabel)
    }

    private func testcaseLabel(className: String?, name: String?) -> String? {
        let components = [sanitizedLabel(className), sanitizedLabel(name)].compactMap { $0 }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: ".")
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

    private func qualifiedElementName(elementName: String, qName: String?) -> String {
        guard let qName, !qName.isEmpty else { return elementName }
        return qName
    }

    private let previewLabelLimit = 6
    private let characterLimit = 80
}
