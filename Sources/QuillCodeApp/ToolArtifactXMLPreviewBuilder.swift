import Foundation

enum ToolArtifactXMLPreviewBuilder {
    static func xmlPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactXMLPreview? {
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
            let collector = XMLPreviewCollector()
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

    private static let byteLimit = 64 * 1_024
}

private final class XMLPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var childLabels: [String] = []
    private var namespaceLabels: Set<String> = []
    private(set) var elementCount = 0
    private(set) var attributeCount = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let label = sanitizedLabel(qualifiedElementName(elementName: elementName, qName: qName))
        if depth == 0 {
            rootElementLabel = label
        } else if depth == 1 {
            childLabels.append(label)
        }
        elementCount += 1
        countAttributes(attributeDict)
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

    func preview(fileSize: Int) -> ToolArtifactXMLPreview? {
        guard let rootElementLabel else { return nil }
        let children = previewLabels(for: childLabels)
        return ToolArtifactXMLPreview(
            rootElementLabel: rootElementLabel,
            elementCount: elementCount,
            attributeCount: attributeCount,
            namespaceCount: namespaceLabels.count,
            childPreviewLabel: previewLabel(for: childLabels),
            childPreviewLabels: children,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private func countAttributes(_ attributeDict: [String: String]) {
        for key in attributeDict.keys {
            if key == "xmlns" || key.hasPrefix("xmlns:") {
                namespaceLabels.insert(key)
            } else {
                attributeCount += 1
            }
        }
    }

    private func previewLabel(for labels: [String]) -> String? {
        let visibleLabels = previewLabels(for: labels)
        guard !visibleLabels.isEmpty else { return nil }
        let remainder = Set(labels).count - visibleLabels.count
        return ([visibleLabels.joined(separator: ", ")] + (remainder > 0 ? ["+\(remainder) more"] : []))
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func previewLabels(for labels: [String]) -> [String] {
        Array(Set(labels).sorted().prefix(keyPreviewLimit))
    }

    private func sanitizedLabel(_ label: String) -> String {
        let collapsedWhitespace = label
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "(unnamed element)" : collapsedWhitespace).prefix(characterLimit))
    }

    private func qualifiedElementName(elementName: String, qName: String?) -> String {
        guard let qName, !qName.isEmpty else { return elementName }
        return qName
    }

    private let keyPreviewLimit = 6
    private let characterLimit = 80
}
