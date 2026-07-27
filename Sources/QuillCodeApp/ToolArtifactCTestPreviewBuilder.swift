import Foundation

enum ToolArtifactCTestPreviewBuilder {
    static func ctestPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCTestPreview? {
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
            let collector = CTestPreviewCollector()
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

private final class CTestPreviewCollector: NSObject, XMLParserDelegate {
    private enum CaptureTarget {
        case testName
        case testFullName
        case measurementValue
    }

    private var depth = 0
    private var rootElementLabel: String?
    private var sawTestingElement = false
    private var activeTestStatus: String?
    private var activeTestName: String?
    private var activeTestFullName: String?
    private var activeMeasurementName: String?
    private var activeCaptureTarget: CaptureTarget?
    private var capturedText = ""
    private var testCount = 0
    private var passedCount = 0
    private var failedCount = 0
    private var notRunCount = 0
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
        }

        switch label {
        case "Testing":
            sawTestingElement = true
        case "Test":
            beginTest(attributeDict)
        case "Name":
            beginCapture(.testName)
        case "FullName":
            beginCapture(.testFullName)
        case "NamedMeasurement":
            activeMeasurementName = sanitizedLabel(attributeDict["name"])
        case "Value":
            if activeMeasurementName == "Execution Time" {
                beginCapture(.measurementValue)
            }
        default:
            break
        }
        depth += 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard activeCaptureTarget != nil else { return }
        capturedText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let label = localElementName(elementName: elementName, qName: qName)
        finishCaptureIfNeeded(closingElement: label)

        switch label {
        case "NamedMeasurement":
            activeMeasurementName = nil
        case "Test":
            finishTest()
        default:
            break
        }
        depth = max(0, depth - 1)
    }

    func preview(fileSize: Int) -> ToolArtifactCTestPreview? {
        guard rootElementLabel == "Site",
              sawTestingElement,
              testCount > 0
        else {
            return nil
        }
        return ToolArtifactCTestPreview(
            testCount: testCount,
            passedCount: passedCount,
            failedCount: failedCount,
            notRunCount: notRunCount,
            durationLabel: hasDuration ? durationLabel(for: durationSeconds) : nil,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            failurePreviewLabels: Array(failureLabels.prefix(previewLabelLimit))
        )
    }

    private func beginTest(_ attributes: [String: String]) {
        activeTestStatus = sanitizedLabel(attributes["Status"])?.lowercased()
        activeTestName = nil
        activeTestFullName = nil
        activeMeasurementName = nil
        activeCaptureTarget = nil
        capturedText = ""
    }

    private func finishTest() {
        guard let status = activeTestStatus else { return }
        testCount += 1
        switch status {
        case "passed":
            passedCount += 1
        case "notrun", "not run", "disabled":
            notRunCount += 1
        default:
            failedCount += 1
            if let label = activeTestFullName ?? activeTestName,
               !failureLabels.contains(label) {
                failureLabels.append(label)
            }
        }
        activeTestStatus = nil
        activeTestName = nil
        activeTestFullName = nil
        activeMeasurementName = nil
        activeCaptureTarget = nil
        capturedText = ""
    }

    private func beginCapture(_ target: CaptureTarget) {
        activeCaptureTarget = target
        capturedText = ""
    }

    private func finishCaptureIfNeeded(closingElement label: String) {
        guard let target = activeCaptureTarget else { return }
        switch (target, label) {
        case (.testName, "Name"):
            activeTestName = sanitizedLabel(capturedText)
            endCapture()
        case (.testFullName, "FullName"):
            activeTestFullName = sanitizedLabel(capturedText)
            endCapture()
        case (.measurementValue, "Value"):
            if let seconds = sanitizedLabel(capturedText).flatMap(Double.init), seconds >= 0 {
                hasDuration = true
                durationSeconds += seconds
            }
            endCapture()
        default:
            break
        }
    }

    private func endCapture() {
        activeCaptureTarget = nil
        capturedText = ""
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
