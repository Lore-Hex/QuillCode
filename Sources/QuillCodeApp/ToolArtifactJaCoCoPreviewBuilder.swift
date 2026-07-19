import Foundation

enum ToolArtifactJaCoCoPreviewBuilder {
    static func jaCoCoPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactJaCoCoPreview? {
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
            let collector = JaCoCoPreviewCollector()
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

private final class JaCoCoPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var reportNameLabel: String?
    private var packageCount = 0
    private var sourceFileCount = 0
    private var classCount = 0
    private var lineCoveredCount: Int?
    private var lineMissedCount: Int?
    private var branchCoveredCount: Int?
    private var branchMissedCount: Int?
    private var methodCoveredCount: Int?
    private var methodMissedCount: Int?
    private var classCoveredCount: Int?
    private var classMissedCount: Int?
    private var hasJaCoCoMarker = false
    private var packageLabels: [String] = []
    private var sourceFileLabels: [String] = []

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
            reportNameLabel = sanitizedLabel(attributeDict["name"])
        }

        switch label {
        case "sessioninfo":
            hasJaCoCoMarker = true
        case "package":
            recordPackage(attributeDict)
        case "sourcefile":
            recordSourceFile(attributeDict)
        case "class":
            classCount += 1
        case "counter" where depth == 1:
            recordRootCounter(attributeDict)
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

    func preview(fileSize: Int) -> ToolArtifactJaCoCoPreview? {
        guard rootElementLabel == "report", hasJaCoCoMarker else { return nil }
        return ToolArtifactJaCoCoPreview(
            reportNameLabel: reportNameLabel,
            packageCount: packageCount,
            sourceFileCount: sourceFileCount,
            classCount: classCount,
            lineCoveredCount: lineCoveredCount,
            lineMissedCount: lineMissedCount,
            branchCoveredCount: branchCoveredCount,
            branchMissedCount: branchMissedCount,
            methodCoveredCount: methodCoveredCount,
            methodMissedCount: methodMissedCount,
            classCoveredCount: classCoveredCount,
            classMissedCount: classMissedCount,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            packagePreviewLabels: Array(packageLabels.prefix(previewLabelLimit)),
            sourceFilePreviewLabels: Array(sourceFileLabels.prefix(previewLabelLimit))
        )
    }

    private func recordPackage(_ attributes: [String: String]) {
        hasJaCoCoMarker = true
        packageCount += 1
        appendUniqueLabel(sanitizedLabel(attributes["name"]), to: &packageLabels)
    }

    private func recordSourceFile(_ attributes: [String: String]) {
        hasJaCoCoMarker = true
        sourceFileCount += 1
        appendUniqueLabel(sanitizedLabel(attributes["name"]), to: &sourceFileLabels)
    }

    private func recordRootCounter(_ attributes: [String: String]) {
        guard let type = sanitizedLabel(attributes["type"])?.uppercased(),
              let missed = intAttribute("missed", in: attributes),
              let covered = intAttribute("covered", in: attributes)
        else {
            return
        }
        hasJaCoCoMarker = true
        switch type {
        case "LINE":
            lineMissedCount = missed
            lineCoveredCount = covered
        case "BRANCH":
            branchMissedCount = missed
            branchCoveredCount = covered
        case "METHOD":
            methodMissedCount = missed
            methodCoveredCount = covered
        case "CLASS":
            classMissedCount = missed
            classCoveredCount = covered
        default:
            break
        }
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
