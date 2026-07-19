import Foundation

enum ToolArtifactCoberturaPreviewBuilder {
    static func coberturaPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCoberturaPreview? {
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
            let collector = CoberturaPreviewCollector()
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

private final class CoberturaPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var versionLabel: String?
    private var lineCoveredCount: Int?
    private var lineValidCount: Int?
    private var branchCoveredCount: Int?
    private var branchValidCount: Int?
    private var lineRateLabel: String?
    private var branchRateLabel: String?
    private var packageCount = 0
    private var classCount = 0
    private var packageLabels: [String] = []
    private var classLabels: [String] = []
    private var hasCoberturaMarker = false

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
            recordCoverage(attributeDict)
        }

        switch label {
        case "package":
            recordPackage(attributeDict)
        case "class":
            recordClass(attributeDict)
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

    func preview(fileSize: Int) -> ToolArtifactCoberturaPreview? {
        guard rootElementLabel == "coverage", hasCoberturaMarker else { return nil }
        return ToolArtifactCoberturaPreview(
            versionLabel: versionLabel,
            packageCount: packageCount,
            classCount: classCount,
            lineCoveredCount: lineCoveredCount,
            lineValidCount: lineValidCount,
            branchCoveredCount: branchCoveredCount,
            branchValidCount: branchValidCount,
            lineRateLabel: lineRateLabel,
            branchRateLabel: branchRateLabel,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            packagePreviewLabels: Array(packageLabels.prefix(previewLabelLimit)),
            classPreviewLabels: Array(classLabels.prefix(previewLabelLimit))
        )
    }

    private func recordCoverage(_ attributes: [String: String]) {
        versionLabel = sanitizedLabel(attributes["version"])
        lineCoveredCount = intAttribute("lines-covered", in: attributes)
        lineValidCount = intAttribute("lines-valid", in: attributes)
        branchCoveredCount = intAttribute("branches-covered", in: attributes)
        branchValidCount = intAttribute("branches-valid", in: attributes)
        lineRateLabel = rateLabel(attributes["line-rate"])
        branchRateLabel = rateLabel(attributes["branch-rate"])
        hasCoberturaMarker = attributes["line-rate"] != nil
            || attributes["branch-rate"] != nil
            || attributes["lines-covered"] != nil
            || attributes["lines-valid"] != nil
            || attributes["branches-covered"] != nil
            || attributes["branches-valid"] != nil
    }

    private func recordPackage(_ attributes: [String: String]) {
        packageCount += 1
        appendUniqueLabel(sanitizedLabel(attributes["name"]), to: &packageLabels)
    }

    private func recordClass(_ attributes: [String: String]) {
        classCount += 1
        let name = sanitizedLabel(attributes["name"])
        let filename = sanitizedLabel(attributes["filename"])
        let label: String?
        switch (name, filename) {
        case let (name?, filename?) where name != filename:
            label = "\(name) · \(filename)"
        case let (name?, _):
            label = name
        case let (_, filename?):
            label = filename
        default:
            label = nil
        }
        appendUniqueLabel(label, to: &classLabels)
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

    private func rateLabel(_ label: String?) -> String? {
        guard let label = sanitizedLabel(label),
              let rate = Double(label),
              rate >= 0
        else {
            return nil
        }
        let percent = min(rate, 1) * 100
        let rounded = (percent * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : "\(rounded)%"
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
