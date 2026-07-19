import Foundation

enum ToolArtifactCheckstylePreviewBuilder {
    static func checkstylePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCheckstylePreview? {
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

            let collector = CheckstylePreviewCollector()
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

private final class CheckstylePreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var fileCount = 0
    private var issueCount = 0
    private var errorCount = 0
    private var warningCount = 0
    private var infoCount = 0
    private var ignoreCount = 0
    private var otherSeverityCount = 0
    private var fileLabels: [String] = []
    private var sourceLabels: [String] = []

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
        if label == "file" {
            recordFile(attributeDict)
        } else if label == "error" {
            recordIssue(attributeDict)
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

    func preview(fileSize: Int) -> ToolArtifactCheckstylePreview? {
        guard rootElementLabel == "checkstyle",
              fileCount > 0 || issueCount > 0
        else {
            return nil
        }
        return ToolArtifactCheckstylePreview(
            fileCount: fileCount,
            issueCount: issueCount,
            errorCount: errorCount,
            warningCount: warningCount,
            infoCount: infoCount,
            ignoreCount: ignoreCount,
            otherSeverityCount: otherSeverityCount,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            filePreviewLabels: Array(fileLabels.prefix(previewLabelLimit)),
            sourcePreviewLabels: Array(sourceLabels.prefix(previewLabelLimit))
        )
    }

    private func recordFile(_ attributes: [String: String]) {
        fileCount += 1
        appendUnique(sanitizedPathLabel(attributes["name"]), to: &fileLabels)
    }

    private func recordIssue(_ attributes: [String: String]) {
        issueCount += 1
        switch sanitizedLabel(attributes["severity"])?.lowercased() {
        case "error":
            errorCount += 1
        case "warning":
            warningCount += 1
        case "info":
            infoCount += 1
        case "ignore":
            ignoreCount += 1
        default:
            otherSeverityCount += 1
        }
        appendUnique(sanitizedLabel(attributes["source"]), to: &sourceLabels)
    }

    private func appendUnique(_ label: String?, to labels: inout [String]) {
        guard let label, !labels.contains(label) else { return }
        labels.append(label)
    }

    private func sanitizedPathLabel(_ label: String?) -> String? {
        guard let label = sanitizedLabel(label) else { return nil }
        let components = label
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.count > 2 else { return label }
        return components.suffix(3).joined(separator: "/")
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
