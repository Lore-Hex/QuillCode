import Foundation

enum ToolArtifactCloverPreviewBuilder {
    static func cloverPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCloverPreview? {
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
            let collector = CloverPreviewCollector()
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

private final class CloverPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var hasCloverMarker = false
    private var packageCount: Int?
    private var fileCount: Int?
    private var classCount: Int?
    private var methodCoveredCount: Int?
    private var methodCount: Int?
    private var statementCoveredCount: Int?
    private var statementCount: Int?
    private var conditionalCoveredCount: Int?
    private var conditionalCount: Int?
    private var elementCoveredCount: Int?
    private var elementCount: Int?
    private var projectLabels: [String] = []
    private var fileLabels: [String] = []

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
            hasCloverMarker = attributeDict["clover"] != nil || attributeDict["generated"] != nil
        }

        switch label {
        case "project":
            hasCloverMarker = true
            appendUniqueLabel(sanitizedLabel(attributeDict["name"]), to: &projectLabels)
        case "metrics":
            hasCloverMarker = true
            recordMetrics(attributeDict)
        case "file":
            appendUniqueLabel(fileLabel(attributeDict), to: &fileLabels)
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

    func preview(fileSize: Int) -> ToolArtifactCloverPreview? {
        guard rootElementLabel == "coverage", hasCloverMarker else { return nil }
        return ToolArtifactCloverPreview(
            packageCount: packageCount,
            fileCount: fileCount,
            classCount: classCount,
            methodCoveredCount: methodCoveredCount,
            methodCount: methodCount,
            statementCoveredCount: statementCoveredCount,
            statementCount: statementCount,
            conditionalCoveredCount: conditionalCoveredCount,
            conditionalCount: conditionalCount,
            elementCoveredCount: elementCoveredCount,
            elementCount: elementCount,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            projectPreviewLabels: Array(projectLabels.prefix(previewLabelLimit)),
            filePreviewLabels: Array(fileLabels.prefix(previewLabelLimit))
        )
    }

    private func recordMetrics(_ attributes: [String: String]) {
        packageCount = intAttribute("packages", in: attributes) ?? packageCount
        fileCount = intAttribute("files", in: attributes) ?? fileCount
        classCount = intAttribute("classes", in: attributes) ?? classCount
        methodCoveredCount = intAttribute("coveredmethods", in: attributes) ?? methodCoveredCount
        methodCount = intAttribute("methods", in: attributes) ?? methodCount
        statementCoveredCount = intAttribute("coveredstatements", in: attributes) ?? statementCoveredCount
        statementCount = intAttribute("statements", in: attributes) ?? statementCount
        conditionalCoveredCount = intAttribute("coveredconditionals", in: attributes) ?? conditionalCoveredCount
        conditionalCount = intAttribute("conditionals", in: attributes) ?? conditionalCount
        elementCoveredCount = intAttribute("coveredelements", in: attributes) ?? elementCoveredCount
        elementCount = intAttribute("elements", in: attributes) ?? elementCount
    }

    private func fileLabel(_ attributes: [String: String]) -> String? {
        sanitizedLabel(attributes["path"]) ?? sanitizedLabel(attributes["name"])
    }

    private func appendUniqueLabel(_ label: String?, to labels: inout [String]) {
        guard let label, !labels.contains(label) else { return }
        labels.append(label)
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
    private let characterLimit = 96
}
